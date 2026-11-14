# SPDX-License-Identifier: MPL-2.0
require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'

workflow = YAML.load_file('.github/workflows/static-analysis-gate.yml')
step = ->(job, name) { workflow.fetch('jobs').fetch(job).fetch('steps').find { |s| s['name'] == name }.fetch('run') }
assail = step.call('panic-attack-assail', 'Run panic-attack assail')
build = step.call('hypatia-scan', 'Clone and build Hypatia')
Dir.mktmpdir('scanner-gate-') do |dir|
  bin = File.join(dir, 'bin')
  FileUtils.mkdir_p(bin)
  File.write(File.join(bin, 'panic-attack'), "#!/bin/bash\nprintf '%s' \"$REPORT\"\nprintf '%s\\n' 'scanner diagnostic' >&2\n")
  File.write(File.join(bin, 'git'), <<~SH)
    #!/bin/bash
    test "$FAIL_STAGE" != clone || exit 71
    mkdir -p "${@: -1}"
    touch "${@: -1}/mix.exs" "${@: -1}/hypatia-cli.sh"
    chmod +x "${@: -1}/hypatia-cli.sh"
  SH
  File.write(File.join(bin, 'mix'), <<~SH)
    #!/bin/bash
    test "$FAIL_STAGE" != "$1" || exit 72
  SH
  Dir.children(bin).each { |f| File.chmod(0o755, File.join(bin, f)) }
  output = File.join(dir, 'outputs')
  env = { 'PATH' => "#{bin}:/usr/bin:/bin", 'GITHUB_OUTPUT' => output, 'RUNNER_TEMP' => dir }
  ['[]', '[{"severity":"critical"}]'].each do |report|
    File.write(output, '')
    log, result = Open3.capture2e(env.merge('REPORT' => report), 'bash', '-e', '-o', 'pipefail', '-c', assail, chdir: dir)
    abort log unless result.success?
    abort 'critical finding was lost' if report.include?('critical') && !File.read(output).include?("critical=1\n")
  end
  ['', '{}', 'null', '"text"', 'broken JSON'].each do |report|
    log, result = Open3.capture2e(env.merge('REPORT' => report), 'bash', '-e', '-o', 'pipefail', '-c', assail, chdir: dir)
    abort "invalid payload accepted: #{report}\n#{log}" if result.success?
  end
  contaminated = assail.sub('> panic-attack-findings.json', '> panic-attack-findings.json 2>&1')
  abort 'stderr redirection control did not match the workflow' if contaminated == assail
  log, result = Open3.capture2e(env.merge('REPORT' => '[]'), 'bash', '-e', '-o', 'pipefail', '-c', contaminated, chdir: dir)
  abort "stderr contamination was accepted: #{log}" if result.success?
  ['', 'clone', 'deps.get', 'escript.build'].each do |stage|
    FileUtils.rm_rf(File.join(dir, 'hypatia'))
    File.write(output, '')
    log, result = Open3.capture2e(env.merge('FAIL_STAGE' => stage), 'bash', '-e', '-o', 'pipefail', '-c', build, chdir: dir)
    abort "unexpected build result for #{stage}: #{log}" unless result.success? == stage.empty?
    abort 'failed setup reported ready' if !stage.empty? && File.read(output).include?('ready=true')
  end
end
puts 'PASS: valid reports, critical finding, malformed payloads, and clone/dependency/build failure controls'
