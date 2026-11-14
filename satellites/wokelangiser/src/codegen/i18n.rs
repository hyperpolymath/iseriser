// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Internationalisation (i18n) module for wokelangiser — extracts translatable
// strings from source files, generates locale template files, and produces
// a translation key manifest for integration with existing i18n frameworks.

use anyhow::{Context, Result};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::abi::{I18nString, Locale, LocaleFile};
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Locale file generation
// ---------------------------------------------------------------------------

/// Generate locale files for all supported locales based on extracted strings.
///
/// Output structure:
///   {output_dir}/i18n/
///     en-GB.json    — default locale with original values
///     fr-FR.json    — template with keys but empty values (to be translated)
///     de-DE.json    — template with keys but empty values
///     ...
///     keys.json     — key manifest with metadata (source file, line, context)
pub fn generate_locale_files(
    manifest: &Manifest,
    strings: &[I18nString],
    output_dir: &str,
) -> Result<Vec<LocaleFile>> {
    let i18n_dir = Path::new(output_dir).join("i18n");
    fs::create_dir_all(&i18n_dir)
        .with_context(|| format!("Failed to create i18n output dir: {}", i18n_dir.display()))?;

    let mut locale_files = Vec::new();

    // Generate the default locale file with all extracted values.
    let default_locale = Locale::new(&manifest.i18n.default_locale);
    let default_translations: Vec<(String, String)> = strings
        .iter()
        .map(|s| (s.key.clone(), s.default_value.clone()))
        .collect();

    let default_file = LocaleFile {
        locale: default_locale.clone(),
        translations: default_translations,
    };

    write_locale_json(&i18n_dir, &default_file)?;
    locale_files.push(default_file);

    // Generate template files for all non-default supported locales.
    // These contain the same keys but with empty values, ready for translation.
    for locale_tag in &manifest.i18n.supported_locales {
        if locale_tag == &manifest.i18n.default_locale {
            continue; // already generated above
        }
        let locale = Locale::new(locale_tag);
        let translations: Vec<(String, String)> = strings
            .iter()
            .map(|s| (s.key.clone(), String::new()))
            .collect();

        let locale_file = LocaleFile {
            locale: locale.clone(),
            translations,
        };

        write_locale_json(&i18n_dir, &locale_file)?;
        locale_files.push(locale_file);
    }

    // Generate the key manifest with metadata about each extracted string.
    let keys_manifest = generate_keys_manifest(strings);
    fs::write(i18n_dir.join("keys.json"), &keys_manifest).context("Failed to write keys.json")?;

    println!(
        "  Generated {} locale files with {} keys in {}",
        locale_files.len(),
        strings.len(),
        i18n_dir.display()
    );

    Ok(locale_files)
}

/// Write a single locale file as JSON.
/// Format: { "key1": "value1", "key2": "value2", ... }
fn write_locale_json(i18n_dir: &Path, locale_file: &LocaleFile) -> Result<()> {
    let map: BTreeMap<&str, &str> = locale_file
        .translations
        .iter()
        .map(|(k, v)| (k.as_str(), v.as_str()))
        .collect();

    let json = serde_json::to_string_pretty(&map).context("Failed to serialise locale file")?;

    let filename = format!("{}.json", locale_file.locale.tag);
    fs::write(i18n_dir.join(&filename), &json)
        .with_context(|| format!("Failed to write locale file: {}", filename))?;

    Ok(())
}

/// Generate a JSON manifest of all translation keys with metadata.
/// This helps translators understand the context of each string.
fn generate_keys_manifest(strings: &[I18nString]) -> String {
    let mut entries = Vec::new();
    for s in strings {
        let context = s.context.as_deref().unwrap_or("none");
        entries.push(format!(
            r#"    {{
      "key": "{}",
      "default_value": "{}",
      "source_file": "{}",
      "line": {},
      "context": "{}"
    }}"#,
            escape_json(&s.key),
            escape_json(&s.default_value),
            escape_json(&s.source_file),
            s.line,
            escape_json(context),
        ));
    }

    format!(
        "{{\n  \"total_keys\": {},\n  \"keys\": [\n{}\n  ]\n}}\n",
        strings.len(),
        entries.join(",\n")
    )
}

/// Minimal JSON string escaping for embedded values.
fn escape_json(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

// ---------------------------------------------------------------------------
// i18n integration code generation
// ---------------------------------------------------------------------------

/// Generate a lightweight i18n integration module that loads locale files
/// and provides a `t(key)` translation function.
pub fn generate_i18n_module(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let i18n_dir = Path::new(output_dir).join("i18n");
    fs::create_dir_all(&i18n_dir)?;

    let supported: Vec<String> = manifest
        .i18n
        .supported_locales
        .iter()
        .map(|l| format!("\"{}\"", l))
        .collect();

    let module_code = format!(
        r#"// SPDX-License-Identifier: MPL-2.0
// Generated by wokelangiser — i18n integration module
// Project: {project}
// Default locale: {default_locale}
// DO NOT EDIT — regenerate with `wokelangiser generate`

/**
 * Lightweight i18n module for wokelangiser-generated translations.
 *
 * Usage:
 *   import {{ t, setLocale }} from './i18n/i18n.js';
 *   setLocale('fr-FR');
 *   console.log(t('str_1')); // translated string
 */

const SUPPORTED_LOCALES = [{supported}];
const DEFAULT_LOCALE = "{default_locale}";

let currentLocale = DEFAULT_LOCALE;
let translations = {{}};

/**
 * Load translations for a locale from the corresponding JSON file.
 * @param {{string}} locale - BCP 47 locale tag.
 * @returns {{Promise<Object>}} The loaded translations object.
 */
async function loadLocale(locale) {{
  if (!SUPPORTED_LOCALES.includes(locale)) {{
    console.warn(`[wokelangiser i18n] Unsupported locale: ${{locale}}, falling back to ${{DEFAULT_LOCALE}}`);
    locale = DEFAULT_LOCALE;
  }}
  try {{
    const response = await fetch(`./${{locale}}.json`);
    translations[locale] = await response.json();
  }} catch (err) {{
    console.error(`[wokelangiser i18n] Failed to load locale ${{locale}}:`, err);
    translations[locale] = {{}};
  }}
  return translations[locale];
}}

/**
 * Set the active locale and load its translations.
 * @param {{string}} locale - BCP 47 locale tag.
 */
export async function setLocale(locale) {{
  currentLocale = locale;
  if (!translations[locale]) {{
    await loadLocale(locale);
  }}
}}

/**
 * Translate a key using the current locale.
 * Falls back to the default locale if the key is not translated,
 * and to the key itself as a last resort.
 *
 * @param {{string}} key - The translation key (e.g. "str_1").
 * @returns {{string}} The translated string.
 */
export function t(key) {{
  // Try current locale first.
  if (translations[currentLocale] && translations[currentLocale][key]) {{
    return translations[currentLocale][key];
  }}
  // Fall back to default locale.
  if (translations[DEFAULT_LOCALE] && translations[DEFAULT_LOCALE][key]) {{
    return translations[DEFAULT_LOCALE][key];
  }}
  // Last resort: return the key itself.
  return key;
}}

/**
 * Get the current locale tag.
 * @returns {{string}} The active BCP 47 locale tag.
 */
export function getLocale() {{
  return currentLocale;
}}

/**
 * Get the list of supported locales.
 * @returns {{string[]}} Array of BCP 47 locale tags.
 */
export function getSupportedLocales() {{
  return [...SUPPORTED_LOCALES];
}}

// Initialise with the default locale.
loadLocale(DEFAULT_LOCALE);
"#,
        project = manifest.project.name,
        default_locale = manifest.i18n.default_locale,
        supported = supported.join(", "),
    );

    fs::write(i18n_dir.join("i18n.js"), &module_code).context("Failed to write i18n.js module")?;

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_escape_json() {
        assert_eq!(escape_json("hello"), "hello");
        assert_eq!(escape_json("say \"hi\""), "say \\\"hi\\\"");
        assert_eq!(escape_json("line\nnew"), "line\\nnew");
    }

    #[test]
    fn test_generate_keys_manifest_empty() {
        let manifest = generate_keys_manifest(&[]);
        assert!(manifest.contains("\"total_keys\": 0"));
    }

    #[test]
    fn test_generate_keys_manifest_with_strings() {
        let strings = vec![
            I18nString {
                key: "str_1".to_string(),
                default_value: "Hello World".to_string(),
                source_file: "index.html".to_string(),
                line: 10,
                context: Some("heading".to_string()),
            },
            I18nString {
                key: "str_2".to_string(),
                default_value: "Click here".to_string(),
                source_file: "index.html".to_string(),
                line: 20,
                context: None,
            },
        ];
        let manifest = generate_keys_manifest(&strings);
        assert!(manifest.contains("\"total_keys\": 2"));
        assert!(manifest.contains("Hello World"));
        assert!(manifest.contains("str_1"));
        assert!(manifest.contains("str_2"));
    }

    #[test]
    fn test_locale_file_generation() {
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let output_dir = dir.path().to_str().expect("TODO: handle error");

        let manifest = crate::manifest::Manifest {
            project: crate::manifest::ProjectConfig {
                name: "test".to_string(),
                source_root: ".".to_string(),
            },
            consent: Default::default(),
            accessibility: Default::default(),
            i18n: crate::manifest::I18nConfig {
                default_locale: "en-GB".to_string(),
                supported_locales: vec!["en-GB".to_string(), "fr-FR".to_string()],
                extract_strings: true,
            },
            report: Default::default(),
        };

        let strings = vec![I18nString {
            key: "str_1".to_string(),
            default_value: "Hello".to_string(),
            source_file: "test.html".to_string(),
            line: 1,
            context: None,
        }];

        let files =
            generate_locale_files(&manifest, &strings, output_dir).expect("TODO: handle error");
        assert_eq!(files.len(), 2); // en-GB + fr-FR

        // Check that the default locale file has the value.
        let en_path = dir.path().join("i18n").join("en-GB.json");
        let en_content = std::fs::read_to_string(en_path).expect("TODO: handle error");
        assert!(en_content.contains("Hello"));

        // Check that the fr-FR file has empty values.
        let fr_path = dir.path().join("i18n").join("fr-FR.json");
        let fr_content = std::fs::read_to_string(fr_path).expect("TODO: handle error");
        assert!(fr_content.contains("str_1"));
        // The value should be empty string.
        assert!(fr_content.contains("\"str_1\": \"\""));
    }
}
