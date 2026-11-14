-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 (CAPSTONE): the end-to-end ABI SOUNDNESS CERTIFICATE for Oblibeniser.
|||
||| This module proves no new domain theorem. It ASSEMBLES the already-proven
||| facts of every prior layer into a single inhabited record value. The point
||| is composition: `abiContractDischarged` only typechecks if every layer it
||| draws on is genuinely sound. If any underlying proof were vacuous or broken,
||| this capstone value would fail to elaborate.
|||
||| It ties together the full ABI contract:
|||
|||   manifest (Result codes, Op family in Types)
|||     -> Layer-2 flagship   : reversibility round-trip (Semantics.certify /
|||                              Semantics.reversible, packaged as `IsReversible`)
|||     -> Layer-3 invariant   : the operations form a GROUP under sequencing,
|||                              with a genuine two-sided inverse
|||                              (Invariants.groupInverse, `IsGroupInverse`)
|||     -> Layer-4 FFI seam    : the wire encoding is injective, so distinct ABI
|||                              outcomes never collide on the C boundary
|||                              (FfiSeam.resultToIntInjective)
|||
||| into ONE end-to-end soundness statement. The non-vacuity control at the
||| bottom (`okErrorWireDistinct`) re-derives, through the very injectivity field
||| stored in the certificate, that `Ok` and `Error` cannot share a wire code —
||| so the FFI field is a real injection, not a constant. The adversarial harness
||| (checked out of tree) confirms a bogus certificate cannot be constructed.

module Oblibeniser.ABI.Capstone

import Oblibeniser.ABI.Types
import Oblibeniser.ABI.Semantics
import Oblibeniser.ABI.Invariants
import Oblibeniser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The canonical positive-control instance
--------------------------------------------------------------------------------

||| The canonical operation the capstone certifies, built from the exported
||| public `Op` constructors of the Layer-2 model: flip every bit, XOR a fixed
||| mask, then reverse. This is a faithful reconstruction of the flagship
||| positive control (the module-private `Semantics.sample` is not exported, so
||| we rebuild the same shape here from public constructors rather than fake a
||| reference to a private name).
public export
canonOp : Op
canonOp = Seq FlipAll (Seq (XorMask [True, False, True]) Rev)

--------------------------------------------------------------------------------
-- The certificate record
--------------------------------------------------------------------------------

||| One bundled certificate that the whole ABI contract is discharged together.
||| Each field is a real proven fact reused from a prior layer; there is no
||| constructor that lets any field be skipped or forged.
public export
record ABISound where
  constructor MkABISound
  ||| Layer-2 flagship: the canonical operation is reversible (round-trip law),
  ||| as an `IsReversible` certificate built only via the exported `certify`.
  flagshipReversible : IsReversible Capstone.canonOp
  ||| Layer-3 invariant: the canonical operation and its inverse satisfy the
  ||| two-sided group-inverse axioms (deeper than the bare round-trip).
  groupStructured    : IsGroupInverse Capstone.canonOp (invert Capstone.canonOp)
  ||| Layer-4 FFI seam: the wire encoding `resultToInt` is injective, so
  ||| distinct ABI Result codes never collide on the C boundary.
  ffiSeamInjective   : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- THE CAPSTONE VALUE: every layer discharged at once
--------------------------------------------------------------------------------

||| The capstone. Constructed entirely from prior-layer exported theorems:
|||   * `certify`              (Oblibeniser.ABI.Semantics)
|||   * `groupInverse`         (Oblibeniser.ABI.Invariants)
|||   * `resultToIntInjective` (Oblibeniser.ABI.FfiSeam)
||| If any of those proofs were unsound, this definition would not typecheck.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    (certify canonOp)
    (groupInverse canonOp)
    resultToIntInjective

--------------------------------------------------------------------------------
-- Non-vacuity control (the FFI field is a real injection, used live)
--------------------------------------------------------------------------------

||| Re-derive, THROUGH the certificate's own injectivity field, that `Ok` and
||| `Error` cannot share a wire code. If `resultToInt Ok = resultToInt Error`,
||| injectivity would force `Ok = Error`, which is structurally impossible. This
||| proves the stored injectivity is genuine (not a constant collapse), so the
||| certificate is non-vacuous.
export
okErrorWireDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorWireDistinct eq =
  case abiContractDischarged.ffiSeamInjective Ok Error eq of
    Refl impossible
