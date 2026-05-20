-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

-- Aspirational/research-tier proofs split out of multiplayer-fabric-predictive-bvh.
-- These modules are NOT load-bearing for the production C codegen header
-- (`predictive_bvh.h`); they encode model-level claims about the abstract BVH,
-- migration protocol, and authorisation logic, and are currently broken under
-- Lean 4.26. See README.md for the repair roadmap.
import PredictiveBVHResearch.Spatial.Partition
import PredictiveBVHResearch.Spatial.Tree
import PredictiveBVHResearch.Spatial.RefitIncremental
import PredictiveBVHResearch.Protocol.Saturate
import PredictiveBVHResearch.Protocol.Fabric
import PredictiveBVHResearch.Interest.AuthorityInterest
import PredictiveBVHResearch.Relativistic.ReBAC
