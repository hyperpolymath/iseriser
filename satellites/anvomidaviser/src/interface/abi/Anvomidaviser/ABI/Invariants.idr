-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Structural invariants for Anvomidaviser (Idris2 ABI Layer 3).
|||
||| The Layer-2 flagship (`Anvomidaviser.ABI.Semantics`) proves the ISU
||| element-count UPPER bound: a well-formed short program has at most seven
||| elements (`WellFormed p = LTE (length p) 7`). This module proves two
||| genuinely DIFFERENT and DEEPER properties over the SAME `Program` model:
|||
|||   1. DOWNWARD-CLOSURE (monotonicity) of well-formedness under deletion.
|||      If a program is well-formed, then removing the element at ANY position
|||      leaves it well-formed. This is a structural law about how the predicate
|||      behaves under a program transformation — not a restatement of the count
|||      bound. The core is an exact length lemma
|||        `removeAtLen : length (removeAt xs i) = length xs` ... after a `S`,
|||      i.e. deleting one element drops the length by exactly one, which is then
|||      transported through `LTE` via `lteSuccLeft`.
|||
|||   2. A SECOND ISU rule, distinct from the count limit: the MINIMUM-CONTENT
|||      rule. A real program must contain at least one element; the empty
|||      program is not a valid program. This is given as a decidable
|||      proposition `HasContent` with a sound+complete `Dec`, a certifier into
|||      the ABI `Result`, and a non-vacuity (negative) control: the empty
|||      program is provably rejected.
|||
||| FORBIDDEN constructs (believe_me, idris_crash, assert_total, postulate,
||| sorry, %hint hacks, asserted equalities) appear NOWHERE below.

module Anvomidaviser.ABI.Invariants

import Anvomidaviser.ABI.Types
import Anvomidaviser.ABI.Semantics
import Data.Nat
import Data.Fin

%default total

--------------------------------------------------------------------------------
-- Deletion at a position
--------------------------------------------------------------------------------

||| Remove the element at position `i` from a list. The position is a `Fin`
||| indexed by the list length, so it is always in range — there is no failure
||| case and no need for `Maybe`.
public export
removeAt : (xs : List a) -> Fin (length xs) -> List a
removeAt (_ :: xs) FZ     = xs
removeAt (x :: xs) (FS k) = x :: removeAt xs k

--------------------------------------------------------------------------------
-- Exact length lemma: deletion drops the length by exactly one
--------------------------------------------------------------------------------

||| Removing one element at any position yields a list whose length, plus one,
||| equals the original length. Stated this way (rather than with `pred`) so the
||| original `length xs` stays in `S` form for transport through `LTE`.
export
removeAtLen : (xs : List a) -> (i : Fin (length xs)) ->
              S (length (removeAt xs i)) = length xs
removeAtLen (_ :: xs) FZ     = Refl
removeAtLen (x :: xs) (FS k) = cong S (removeAtLen xs k)

--------------------------------------------------------------------------------
-- Downward-closure (monotonicity) of WellFormed under deletion
--------------------------------------------------------------------------------

||| THEOREM (downward-closure / monotonicity). If a program is well-formed
||| (at most seven elements) then deleting the element at any position keeps it
||| well-formed. Deeper than the Layer-2 count bound: it is a closure law about
||| the predicate under a structural transformation.
|||
||| Proof: from `WellFormed p` we have `LTE (length p) 7`. By `removeAtLen`,
||| `S (length (removeAt p i)) = length p`, so rewriting gives
||| `LTE (S (length (removeAt p i))) 7`, and `lteSuccLeft` weakens this to
||| `LTE (length (removeAt p i)) 7` — exactly `WellFormed (removeAt p i)`.
export
wellFormedDownClosed : (p : Program) -> (i : Fin (length p)) ->
                       WellFormed p -> WellFormed (removeAt p i)
wellFormedDownClosed p i (WF prf) =
  let prfS : LTE (S (length (removeAt p i))) 7
           = rewrite removeAtLen p i in prf
   in WF (lteSuccLeft prfS)

||| Specialisation to the head: dropping the first element preserves
||| well-formedness (the `tail` corollary). `p` is required non-empty so that a
||| first element exists; the position is `FZ`.
export
wellFormedTail : (x : SkateElement) -> (xs : Program) ->
                 WellFormed (x :: xs) -> WellFormed xs
wellFormedTail x xs wf = wellFormedDownClosed (x :: xs) FZ wf

--------------------------------------------------------------------------------
-- Second ISU rule: the minimum-content rule (a non-empty program)
--------------------------------------------------------------------------------

||| The minimum-content rule: a valid program contains at least one element.
||| Distinct from the count limit — this is a LOWER bound on content.
public export
data HasContent : Program -> Type where
  HC : {0 x : SkateElement} -> {0 xs : Program} -> HasContent (x :: xs)

||| The empty program has no content. Used as the refutation for the `Dec`
||| (top-level `impossible` clause, per the Idris2 0.7.0 idiom).
export
Uninhabited (HasContent []) where
  uninhabited HC impossible

||| Sound + complete decision procedure for the minimum-content rule.
public export
decHasContent : (p : Program) -> Dec (HasContent p)
decHasContent []        = No uninhabited
decHasContent (_ :: _)  = Yes HC

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound
--------------------------------------------------------------------------------

||| Certify the minimum-content rule into the shared ABI `Result`. A violation
||| is reported as `RuleViolation` (the dedicated ISU-rule failure code).
public export
certifyContent : Program -> Result
certifyContent p = case decHasContent p of
  Yes _ => Ok
  No  _ => RuleViolation

||| Soundness: an `Ok` verdict really does witness the minimum-content rule.
export
certifyContentSound : (p : Program) -> certifyContent p = Ok -> HasContent p
certifyContentSound p prf with (decHasContent p)
  certifyContentSound p prf  | Yes hc = hc
  certifyContentSound p Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive controls (inhabited witnesses)
--------------------------------------------------------------------------------

||| A concrete deletion: removing the middle element of a three-element program.
public export
trimmedProgram : Program
trimmedProgram = removeAt Semantics.goodProgram (FS FZ)

||| Positive control for downward-closure: the well-formed `goodProgram` stays
||| well-formed after deleting its middle element. This is a real transport of
||| the Layer-2 witness through the Layer-3 theorem.
export
trimmedWellFormed : WellFormed Invariants.trimmedProgram
trimmedWellFormed =
  wellFormedDownClosed Semantics.goodProgram (FS FZ) goodWellFormed

||| Positive control for the minimum-content rule.
export
goodHasContent : certifyContent Semantics.goodProgram = Ok
goodHasContent = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls
--------------------------------------------------------------------------------

||| Non-vacuity for the minimum-content rule: the empty program is rejected.
export
emptyRejected : certifyContent [] = RuleViolation
emptyRejected = Refl

||| Stronger negative control: the empty program provably has no content. This
||| rules out a vacuously-true `HasContent`.
export
emptyNoContent : Not (HasContent [])
emptyNoContent = uninhabited

||| Non-vacuity for downward-closure: the theorem genuinely constrains length.
||| Deleting one element from a maximal (7-element) program yields a 6-element
||| program — and that length is exactly what `removeAtLen` reports, machine
||| checked here against the concrete `6`.
public export
fullProgram : Program
fullProgram = [Jump, Spin, StepSequence, Jump, Spin, StepSequence, Jump]

export
fullLenIs7 : length Invariants.fullProgram = 7
fullLenIs7 = Refl

||| After one deletion the length is exactly 6 (a concrete witness that the
||| length lemma is not vacuous on a non-trivial instance).
export
trimFullLenIs6 : length (removeAt Invariants.fullProgram FZ) = 6
trimFullLenIs6 = Refl
