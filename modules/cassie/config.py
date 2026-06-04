def can_build(env, platform):
    # CASSIE's native path pulls heavy research thirdparty (Geogram, Eigen, PMP,
    # Slang) that is not -Werror / -fno-exceptions-clean on the emscripten (Web)
    # and iOS libc++ toolchains. Gate the in-engine module off those targets;
    # Linux/Windows/macOS/Android keep the native path.
    return platform not in ("web", "ios")


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
