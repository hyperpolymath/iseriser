-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Eclexiaiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. Functions cover:
|||   - Library lifecycle (init, free)
|||   - Energy measurement (RAPL, IPMI, software estimation)
|||   - Carbon intensity API (WattTime, Electricity Maps)
|||   - Budget enforcement (check measurement against proven bound)
|||   - Sustainability report generation (CSRD-compatible)
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Eclexiaiser.ABI.Foreign

import Eclexiaiser.ABI.Types
import Eclexiaiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the eclexiaiser library.
||| Allocates a measurement context, detects available hardware counters
||| (RAPL, IPMI), and configures the carbon API client.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:eclexiaiser_init, libeclexiaiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources.
||| Flushes any pending measurements, closes API connections, frees memory.
export
%foreign "C:eclexiaiser_free, libeclexiaiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Energy Measurement
--------------------------------------------------------------------------------

||| Start measuring energy for a function.
||| Reads the current hardware counter value and stores it in the context.
||| The function_id is a hash of the fully-qualified function name.
export
%foreign "C:eclexiaiser_start_measurement, libeclexiaiser"
prim__startMeasurement : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: begin energy measurement for a function
export
startMeasurement : Handle -> (functionId : Bits64) -> IO (Either Result ())
startMeasurement h funcId = do
  result <- primIO (prim__startMeasurement (handlePtr h) funcId)
  pure $ case result of
    0 => Right ()
    7 => Left CounterUnavailable
    _ => Left Error

||| Stop measuring energy for a function.
||| Returns the energy consumed in microjoules since startMeasurement was called.
export
%foreign "C:eclexiaiser_stop_measurement, libeclexiaiser"
prim__stopMeasurement : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: end energy measurement, get microjoules consumed
export
stopMeasurement : Handle -> (functionId : Bits64) -> IO (Either Result Bits64)
stopMeasurement h funcId = do
  result <- primIO (prim__stopMeasurement (handlePtr h) funcId)
  if result == 0
    then pure (Left Error)
    else pure (Right result)

||| Read instantaneous power draw in milliwatts.
||| Uses RAPL on x86_64, IPMI on server hardware, estimation otherwise.
export
%foreign "C:eclexiaiser_read_power_mw, libeclexiaiser"
prim__readPowerMw : Bits64 -> PrimIO Bits64

||| Safe wrapper: read current power draw
export
readPowerMw : Handle -> IO (Either Result Bits64)
readPowerMw h = do
  result <- primIO (prim__readPowerMw (handlePtr h))
  if result == 0
    then pure (Left CounterUnavailable)
    else pure (Right result)

--------------------------------------------------------------------------------
-- Carbon Intensity API
--------------------------------------------------------------------------------

||| Query carbon intensity for a grid zone from the configured API.
||| Returns milligrams CO2 per kWh for the specified zone.
||| Uses cached values if available and fresh enough.
export
%foreign "C:eclexiaiser_query_carbon_intensity, libeclexiaiser"
prim__queryCarbonIntensity : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: query carbon intensity for a zone
export
queryCarbonIntensity : Handle -> (zoneId : Bits32) -> IO (Either Result CarbonIntensity)
queryCarbonIntensity h zoneId = do
  intensity <- primIO (prim__queryCarbonIntensity (handlePtr h) zoneId)
  if intensity == 0
    then pure (Left Error)
    else pure (Right (MkCarbonIntensity intensity zoneId))

||| Query renewable energy percentage for a grid zone.
||| Returns basis points (0-10000 = 0.00%-100.00%).
export
%foreign "C:eclexiaiser_query_renewable_pct, libeclexiaiser"
prim__queryRenewablePct : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: query renewable percentage
export
queryRenewablePct : Handle -> (zoneId : Bits32) -> IO (Either Result Bits32)
queryRenewablePct h zoneId = do
  pct <- primIO (prim__queryRenewablePct (handlePtr h) zoneId)
  pure (Right pct)

||| Set the carbon API provider (0 = WattTime, 1 = Electricity Maps, 2 = static).
export
%foreign "C:eclexiaiser_set_carbon_api, libeclexiaiser"
prim__setCarbonApi : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: configure carbon API provider
export
setCarbonApi : Handle -> (apiSource : Bits32) -> IO (Either Result ())
setCarbonApi h api = do
  result <- primIO (prim__setCarbonApi (handlePtr h) api)
  pure $ case result of
    0 => Right ()
    _ => Left InvalidParam

--------------------------------------------------------------------------------
-- Budget Enforcement
--------------------------------------------------------------------------------

||| Enforce an energy budget against a measurement.
||| Returns 0 (Ok) if within budget, 5 (BudgetExceeded) otherwise.
export
%foreign "C:eclexiaiser_enforce_energy_budget, libeclexiaiser"
prim__enforceEnergyBudget : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: check energy measurement against budget
export
enforceEnergyBudget : Handle -> EnergyBudget -> (measuredUj : Bits64) -> IO (Either Result ())
enforceEnergyBudget h budget measured = do
  result <- primIO (prim__enforceEnergyBudget (handlePtr h) budget.limitMicrojoules measured)
  pure $ case result of
    0 => Right ()
    5 => Left BudgetExceeded
    _ => Left Error

||| Enforce a carbon limit against a measurement.
||| Returns 0 (Ok) if within limit, 6 (CarbonLimitExceeded) otherwise.
export
%foreign "C:eclexiaiser_enforce_carbon_limit, libeclexiaiser"
prim__enforceCarbonLimit : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: check carbon measurement against limit
export
enforceCarbonLimit : Handle -> (limitMgCO2 : Bits64) -> (measuredMgCO2 : Bits64) -> IO (Either Result ())
enforceCarbonLimit h limit measured = do
  result <- primIO (prim__enforceCarbonLimit (handlePtr h) limit measured)
  pure $ case result of
    0 => Right ()
    6 => Left CarbonLimitExceeded
    _ => Left Error

||| Enforce a composite resource bound (energy + carbon + time + memory).
export
%foreign "C:eclexiaiser_enforce_resource_bound, libeclexiaiser"
prim__enforceResourceBound : Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: enforce all four resource dimensions
export
enforceResourceBound : Handle -> ResourceBound -> ResourceBound -> IO (Either Result ())
enforceResourceBound h bound measured = do
  result <- primIO (prim__enforceResourceBound
    (handlePtr h)
    bound.energyLimitUj bound.carbonLimitMgCO2 bound.timeLimitUs bound.memoryLimitBytes
    measured.energyLimitUj measured.carbonLimitMgCO2 measured.timeLimitUs measured.memoryLimitBytes)
  pure $ case result of
    0 => Right ()
    5 => Left BudgetExceeded
    6 => Left CarbonLimitExceeded
    _ => Left Error

--------------------------------------------------------------------------------
-- Sustainability Report Generation
--------------------------------------------------------------------------------

||| Generate a sustainability report from all accumulated measurements.
||| The report struct is written to the provided buffer pointer.
export
%foreign "C:eclexiaiser_generate_report, libeclexiaiser"
prim__generateReport : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: generate sustainability report
export
generateReport : Handle -> (reportBufferPtr : Bits64) -> IO (Either Result ())
generateReport h buf = do
  result <- primIO (prim__generateReport (handlePtr h) buf)
  pure $ case result of
    0 => Right ()
    4 => Left NullPointer
    _ => Left Error

||| Export a sustainability report as JSON string.
||| Caller must free the returned string.
export
%foreign "C:eclexiaiser_report_to_json, libeclexiaiser"
prim__reportToJson : Bits64 -> PrimIO Bits64

||| Safe wrapper: get report as JSON
export
reportToJson : Handle -> IO (Maybe String)
reportToJson h = do
  ptr <- primIO (prim__reportToJson (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String
    %foreign "C:eclexiaiser_free_string, libeclexiaiser"
    prim__freeString : Bits64 -> PrimIO ()

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:eclexiaiser_last_error, libeclexiaiser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getErrorString ptr))
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getErrorString : Bits64 -> String

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription BudgetExceeded = "Energy budget exceeded"
errorDescription CarbonLimitExceeded = "Carbon intensity limit exceeded"
errorDescription CounterUnavailable = "Hardware energy counter not available"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:eclexiaiser_version, libeclexiaiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__versionString ptr)
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__versionString : Bits64 -> String

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized and hardware counters are available
export
%foreign "C:eclexiaiser_is_initialized, libeclexiaiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)

||| Check which energy counter type is available (0=RAPL, 1=IPMI, 2=estimate)
export
%foreign "C:eclexiaiser_counter_type, libeclexiaiser"
prim__counterType : Bits64 -> PrimIO Bits32

||| Get the available counter type
export
counterType : Handle -> IO Bits32
counterType h = primIO (prim__counterType (handlePtr h))
