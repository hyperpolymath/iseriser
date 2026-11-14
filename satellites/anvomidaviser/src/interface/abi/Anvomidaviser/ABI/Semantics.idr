-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Anvomidaviser (Idris2 ABI Layer 2).
|||
||| Anvomidaviser's headline is "convert ISU notation to formal figure skating
||| programs". A formal program must satisfy ISU well-formedness rules; the
||| canonical structural one is the element-count limit of a short program (at
||| most seven elements). This module models a program as a sequence of skating
||| elements and proves:
|||
|||   1. `WellFormed` — the ISU element-count rule — as a decidable proposition
|||      (LTE the limit), with a sound+complete `Dec`;
|||   2. a certifier proven sound; and
|||   3. positive + negative controls (an over-length program is provably
|||      rejected — the rule is non-vacuous).

module Anvomidaviser.ABI.Semantics

import Anvomidaviser.ABI.Types
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- A minimal but faithful program model
--------------------------------------------------------------------------------

public export
data SkateElement = Jump | Spin | StepSequence

||| A program is an ordered sequence of elements (as parsed from ISU notation).
public export
Program : Type
Program = List SkateElement

||| The ISU short-program element limit.
public export
maxElements : Nat
maxElements = 7

--------------------------------------------------------------------------------
-- ISU well-formedness as a decidable proposition
--------------------------------------------------------------------------------

-- NB: the limit is written as the literal `7` (= `maxElements`) in this
-- constructor's type, because a lowercase name in a constructor signature is
-- auto-bound as a fresh implicit (which would shadow the global constant).
public export
data WellFormed : Program -> Type where
  WF : {0 p : Program} -> LTE (length p) 7 -> WellFormed p

public export
decWellFormed : (p : Program) -> Dec (WellFormed p)
decWellFormed p = case isLTE (length p) maxElements of
  Yes prf => Yes (WF prf)
  No  no  => No (\(WF q) => no q)

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound
--------------------------------------------------------------------------------

public export
certifyProgram : Program -> Result
certifyProgram p = case decWellFormed p of
  Yes _ => Ok
  No  _ => Error

export
certifyProgramSound : (p : Program) -> certifyProgram p = Ok -> WellFormed p
certifyProgramSound p prf with (decWellFormed p)
  certifyProgramSound p prf  | Yes wf = wf
  certifyProgramSound p Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive control
--------------------------------------------------------------------------------

public export
goodProgram : Program
goodProgram = [Jump, Spin, StepSequence]

export
goodAccepts : certifyProgram Semantics.goodProgram = Ok
goodAccepts = Refl

export
goodWellFormed : WellFormed Semantics.goodProgram
goodWellFormed = certifyProgramSound Semantics.goodProgram goodAccepts

--------------------------------------------------------------------------------
-- Negative control: an over-length program is rejected (non-vacuity)
--------------------------------------------------------------------------------

||| Eight elements — one over the ISU short-program limit.
public export
overProgram : Program
overProgram = [Jump, Jump, Jump, Jump, Spin, Spin, Spin, StepSequence]

export
overRejected : certifyProgram Semantics.overProgram = Error
overRejected = Refl
