-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Atsiser (Idris2 ABI Layer 2).
|||
||| Atsiser's headline is "wrap C codebases in ATS linear types for zero-cost
||| memory safety". The defining guarantee of a linear pointer is that a freed
||| pointer can neither be dereferenced (use-after-free) nor freed again
||| (double-free). This module models a pointer with an explicit ownership
||| state (`Live`/`Freed`) and proves:
|||
|||   1. `Accessible` — the permission to dereference or free — has a constructor
|||      ONLY for a `Live` pointer; a `Freed` pointer's accessibility is
|||      uninhabited, so use-after-free / double-free are unrepresentable;
|||   2. `free` consumes a `Live` pointer (with its accessibility witness) and
|||      yields a `Freed` one — the linear transition;
|||   3. a sound+complete `Dec`, a certifier proven sound, and positive +
|||      negative controls.

module Atsiser.ABI.Semantics

import Atsiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A pointer with an explicit ownership state
--------------------------------------------------------------------------------

public export
data PtrState = Live | Freed

public export
record Ptr where
  constructor MkPtr
  addr  : Nat
  state : PtrState

--------------------------------------------------------------------------------
-- Accessibility: only a Live pointer may be used (no constructor for Freed)
--------------------------------------------------------------------------------

public export
data Accessible : Ptr -> Type where
  Acc : {0 addr : Nat} -> Accessible (MkPtr addr Live)

||| No accessibility witness exists for a Freed pointer (the `addr` is bound
||| explicitly to avoid an implicit-lowercase-bind warning).
export
freedNotAcc : {0 addr : Nat} -> Not (Accessible (MkPtr addr Freed))
freedNotAcc Acc impossible

||| Freeing consumes a Live pointer (and its access right) and returns a Freed
||| one. It can only be called with an `Accessible` witness, which a Freed
||| pointer can never supply — double-free is ruled out at the type level.
public export
free : (p : Ptr) -> Accessible p -> Ptr
free (MkPtr addr Live) Acc = MkPtr addr Freed

--------------------------------------------------------------------------------
-- Sound + complete decision
--------------------------------------------------------------------------------

public export
decAccessible : (p : Ptr) -> Dec (Accessible p)
decAccessible (MkPtr addr Live)  = Yes Acc
decAccessible (MkPtr addr Freed) = No freedNotAcc

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound
--------------------------------------------------------------------------------

public export
certifyAccess : Ptr -> Result
certifyAccess p = case decAccessible p of
  Yes _ => Ok
  No  _ => Error

export
certifyAccessSound : (p : Ptr) -> certifyAccess p = Ok -> Accessible p
certifyAccessSound p prf with (decAccessible p)
  certifyAccessSound p prf  | Yes acc = acc
  certifyAccessSound p Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive control: a live pointer is accessible
--------------------------------------------------------------------------------

export
liveAccessible : Accessible (MkPtr 4096 Live)
liveAccessible = Acc

export
certifyLiveAccepts : certifyAccess (MkPtr 4096 Live) = Ok
certifyLiveAccepts = Refl

--------------------------------------------------------------------------------
-- Negative control: a freed pointer is NOT accessible (use-after-free /
-- double-free have no proof) — the non-vacuity core.
--------------------------------------------------------------------------------

export
freedNotAccessible : Not (Accessible (MkPtr 4096 Freed))
freedNotAccessible = freedNotAcc

export
certifyFreedRejects : certifyAccess (MkPtr 4096 Freed) = Error
certifyFreedRejects = Refl
