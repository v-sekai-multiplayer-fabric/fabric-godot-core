def can_build(env, platform):
    # CASSIE's native path pulls heavy research thirdparty (Geogram, Eigen, PMP,
    # Slang). It builds on Linux/Windows/macOS/Android/iOS; only the emscripten
    # (Web) toolchain can't carry it (no -fno-exceptions support for the Geogram
    # throw sites, plus wasm-specific type limits), so gate the module off Web.
    return platform != "web"


def configure(env):
    pass


def get_doc_classes():
    return [
        "CassieBeautifier",
        "CassieBeautifierParams",
        "CassieConstraint",
        "CassieConstraintSolver",
        "CassieCurvenet",
        "CassieCurvenetExtractor",
        "CassieCurvenetKnot",
        "CassieEdgeCollider",
        "CassieFinalStroke",
        "CassieInputStroke",
        "CassieIntersectionConstraint",
        "CassieMirrorPlaneConstraint",
        "CassiePath3D",
        "CassieProfileMover",
        "CassieSketchContext",
        "CassieSketchGraph",
        "CassieSketchGraphEdge",
        "CassieSketchGraphNode",
        "CassieSketcher",
        "CassieSolverParams",
        "CassieStrokePacket",
        "CassieSurface",
        "CassieSurfaceConstraint",
        "CassieSurfaceManager",
        "CassieSurfacePatch",
        "CassieTriangulator",
        "IntrinsicTriangulation",
        "PolygonTriangulation",
        "PolygonTriangulationGodot",
    ]


def get_doc_path():
    return "doc_classes"
