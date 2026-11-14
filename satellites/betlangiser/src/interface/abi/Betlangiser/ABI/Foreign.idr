-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Betlangiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. Functions cover:
|||   - Distribution creation and destruction
|||   - Sampling from distributions
|||   - Distribution combination (sum, product, mixture)
|||   - Ternary logic evaluation
|||   - Confidence interval computation
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Betlangiser.ABI.Foreign

import Betlangiser.ABI.Types
import Betlangiser.ABI.Layout
import Data.So

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the betlangiser engine.
||| Returns a handle to the engine instance, or Nothing on failure.
export
%foreign "C:betlangiser_init, libbetlangiser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up engine resources and free all distributions
export
%foreign "C:betlangiser_free, libbetlangiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Distribution Creation
--------------------------------------------------------------------------------

||| Create a Normal distribution.
||| Parameters: mean (double), stddev (double, must be > 0)
export
%foreign "C:betlangiser_dist_normal, libbetlangiser"
prim__distNormal : Bits64 -> Double -> Double -> PrimIO Bits64

||| Safe wrapper: create a Normal distribution
export
distNormal : Handle -> (mean : Double) -> (stddev : Double) ->
             {auto 0 valid : So (stddev > 0.0)} ->
             IO (Maybe DistributionHandle)
distNormal h mean stddev = do
  ptr <- primIO (prim__distNormal (handlePtr h) mean stddev)
  pure (createDistHandle ptr)

||| Create a Uniform distribution.
||| Parameters: low (double), high (double, must be > low)
export
%foreign "C:betlangiser_dist_uniform, libbetlangiser"
prim__distUniform : Bits64 -> Double -> Double -> PrimIO Bits64

||| Safe wrapper: create a Uniform distribution
export
distUniform : Handle -> (low : Double) -> (high : Double) ->
              {auto 0 valid : So (low < high)} ->
              IO (Maybe DistributionHandle)
distUniform h low high = do
  ptr <- primIO (prim__distUniform (handlePtr h) low high)
  pure (createDistHandle ptr)

||| Create a Beta distribution.
||| Parameters: alpha (double, > 0), beta (double, > 0)
export
%foreign "C:betlangiser_dist_beta, libbetlangiser"
prim__distBeta : Bits64 -> Double -> Double -> PrimIO Bits64

||| Safe wrapper: create a Beta distribution
export
distBeta : Handle -> (alpha : Double) -> (beta : Double) ->
           {auto 0 validA : So (alpha > 0.0)} ->
           {auto 0 validB : So (beta > 0.0)} ->
           IO (Maybe DistributionHandle)
distBeta h alpha beta = do
  ptr <- primIO (prim__distBeta (handlePtr h) alpha beta)
  pure (createDistHandle ptr)

||| Create a Bernoulli distribution.
||| Parameter: p (probability of success, in [0,1])
export
%foreign "C:betlangiser_dist_bernoulli, libbetlangiser"
prim__distBernoulli : Bits64 -> Double -> PrimIO Bits64

||| Safe wrapper: create a Bernoulli distribution
export
distBernoulli : Handle -> ProbabilityValue -> IO (Maybe DistributionHandle)
distBernoulli h p = do
  ptr <- primIO (prim__distBernoulli (handlePtr h) (probValue p))
  pure (createDistHandle ptr)

||| Free a distribution handle
export
%foreign "C:betlangiser_dist_free, libbetlangiser"
prim__distFree : Bits64 -> Bits64 -> PrimIO ()

||| Safe wrapper: free a distribution
export
distFree : Handle -> DistributionHandle -> IO ()
distFree h d = primIO (prim__distFree (handlePtr h) (distHandlePtr d))

--------------------------------------------------------------------------------
-- Sampling
--------------------------------------------------------------------------------

||| Draw a single sample from a distribution
export
%foreign "C:betlangiser_sample_one, libbetlangiser"
prim__sampleOne : Bits64 -> Bits64 -> PrimIO Double

||| Safe wrapper: sample a single value
export
sampleOne : Handle -> DistributionHandle -> IO Double
sampleOne h d = primIO (prim__sampleOne (handlePtr h) (distHandlePtr d))

||| Draw multiple samples into a buffer.
||| Parameters: distribution handle, output buffer pointer, count.
||| Returns result code.
export
%foreign "C:betlangiser_sample_many, libbetlangiser"
prim__sampleMany : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: sample multiple values
export
sampleMany : Handle -> DistributionHandle -> (bufferPtr : Bits64) -> (count : Bits64) ->
             IO (Either Result ())
sampleMany h d buf count = do
  result <- primIO (prim__sampleMany (handlePtr h) (distHandlePtr d) buf count)
  pure $ case result of
    0 => Right ()
    1 => Left Error
    2 => Left InvalidParam
    3 => Left OutOfMemory
    4 => Left NullPointer
    5 => Left InvalidDistribution
    6 => Left SamplingFailed
    _ => Left Error

--------------------------------------------------------------------------------
-- Distribution Combination
--------------------------------------------------------------------------------

||| Combine two distributions by addition (convolution).
||| Returns a new distribution handle representing the sum.
export
%foreign "C:betlangiser_dist_add, libbetlangiser"
prim__distAdd : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: add two distributions
export
distAdd : Handle -> DistributionHandle -> DistributionHandle ->
          IO (Maybe DistributionHandle)
distAdd h d1 d2 = do
  ptr <- primIO (prim__distAdd (handlePtr h) (distHandlePtr d1) (distHandlePtr d2))
  pure (createDistHandle ptr)

||| Combine two distributions by multiplication (product).
export
%foreign "C:betlangiser_dist_multiply, libbetlangiser"
prim__distMultiply : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: multiply two distributions
export
distMultiply : Handle -> DistributionHandle -> DistributionHandle ->
               IO (Maybe DistributionHandle)
distMultiply h d1 d2 = do
  ptr <- primIO (prim__distMultiply (handlePtr h) (distHandlePtr d1) (distHandlePtr d2))
  pure (createDistHandle ptr)

||| Create a mixture distribution from two distributions with weights.
||| weight is the probability of choosing the first distribution.
export
%foreign "C:betlangiser_dist_mixture, libbetlangiser"
prim__distMixture : Bits64 -> Bits64 -> Bits64 -> Double -> PrimIO Bits64

||| Safe wrapper: mixture of two distributions
export
distMixture : Handle -> DistributionHandle -> DistributionHandle ->
              ProbabilityValue -> IO (Maybe DistributionHandle)
distMixture h d1 d2 weight = do
  ptr <- primIO (prim__distMixture (handlePtr h) (distHandlePtr d1) (distHandlePtr d2) (probValue weight))
  pure (createDistHandle ptr)

--------------------------------------------------------------------------------
-- Ternary Logic Evaluation
--------------------------------------------------------------------------------

||| Compare a distribution sample to a threshold, returning TernaryBool.
||| If confidence is below threshold, returns Unknown.
export
%foreign "C:betlangiser_ternary_compare, libbetlangiser"
prim__ternaryCompare : Bits64 -> Bits64 -> Double -> Double -> PrimIO Bits32

||| Safe wrapper: ternary comparison
||| Returns TTrue if P(dist > threshold) >= confidence,
|||         TFalse if P(dist <= threshold) >= confidence,
|||         TUnknown otherwise.
export
ternaryCompare : Handle -> DistributionHandle -> (threshold : Double) ->
                 (confidence : Double) -> IO TernaryBool
ternaryCompare h d threshold conf = do
  result <- primIO (prim__ternaryCompare (handlePtr h) (distHandlePtr d) threshold conf)
  pure $ case intToTernary result of
    Just t => t
    Nothing => TUnknown  -- Defensive fallback

||| Evaluate ternary AND on two distribution comparisons
export
%foreign "C:betlangiser_ternary_and, libbetlangiser"
prim__ternaryAndFFI : Bits32 -> Bits32 -> Bits32

||| Evaluate ternary OR on two distribution comparisons
export
%foreign "C:betlangiser_ternary_or, libbetlangiser"
prim__ternaryOrFFI : Bits32 -> Bits32 -> Bits32

||| Evaluate ternary NOT on a distribution comparison
export
%foreign "C:betlangiser_ternary_not, libbetlangiser"
prim__ternaryNotFFI : Bits32 -> Bits32

--------------------------------------------------------------------------------
-- Confidence Interval Computation
--------------------------------------------------------------------------------

||| Compute a confidence interval for a distribution.
||| Parameters: distribution handle, confidence level (e.g. 0.95).
||| Writes lower, upper, confidence into output struct.
export
%foreign "C:betlangiser_confidence_interval, libbetlangiser"
prim__confidenceInterval : Bits64 -> Bits64 -> Double -> Bits64 -> PrimIO Bits32

||| Safe wrapper: compute confidence interval
export
confidenceInterval : Handle -> DistributionHandle -> (confidence : Double) ->
                     (outputPtr : Bits64) -> IO (Either Result ())
confidenceInterval h d conf outPtr = do
  result <- primIO (prim__confidenceInterval (handlePtr h) (distHandlePtr d) conf outPtr)
  pure $ case result of
    0 => Right ()
    _ => Left Error

--------------------------------------------------------------------------------
-- Distribution Properties
--------------------------------------------------------------------------------

||| Get the mean of a distribution
export
%foreign "C:betlangiser_dist_mean, libbetlangiser"
prim__distMean : Bits64 -> Bits64 -> PrimIO Double

||| Safe wrapper: distribution mean
export
distMean : Handle -> DistributionHandle -> IO Double
distMean h d = primIO (prim__distMean (handlePtr h) (distHandlePtr d))

||| Get the variance of a distribution
export
%foreign "C:betlangiser_dist_variance, libbetlangiser"
prim__distVariance : Bits64 -> Bits64 -> PrimIO Double

||| Safe wrapper: distribution variance
export
distVariance : Handle -> DistributionHandle -> IO Double
distVariance h d = primIO (prim__distVariance (handlePtr h) (distHandlePtr d))

||| Get the distribution tag (type identifier)
export
%foreign "C:betlangiser_dist_tag, libbetlangiser"
prim__distTag : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: get distribution type
export
distTag : Handle -> DistributionHandle -> IO Bits32
distTag h d = primIO (prim__distTag (handlePtr h) (distHandlePtr d))

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:betlangiser_free_string, libbetlangiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:betlangiser_get_string, libbetlangiser"
prim__getResult : Bits64 -> PrimIO Bits64

||| Safe string getter
export
getString : Handle -> IO (Maybe String)
getString h = do
  ptr <- primIO (prim__getResult (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:betlangiser_last_error, libbetlangiser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription InvalidDistribution = "Invalid distribution parameters"
errorDescription SamplingFailed = "Sampling failed"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:betlangiser_version, libbetlangiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:betlangiser_build_info, libbetlangiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if engine is initialized
export
%foreign "C:betlangiser_is_initialized, libbetlangiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
