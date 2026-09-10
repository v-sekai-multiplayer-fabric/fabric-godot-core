# Godot's Linux CI pins ubuntu-22.04 (GCC 11 / clang 14), whose standard
# libraries predate <expected>. The vendored sources return std::expected, so
# probe the real toolchain rather than guessing from a compiler version.

_CXX23_CACHE: dict[str, bool] = {}


def _has_std_expected(env):
    import os
    import subprocess
    import tempfile

    cxx = env.get("CXX") or ""
    key = str(cxx)
    if key in _CXX23_CACHE:
        return _CXX23_CACHE[key]

    src = "#include <expected>\nstd::expected<int, int> f() { return 1; }\n"
    ok = False
    tmpdir = tempfile.mkdtemp(prefix="godot-cxx23-")
    path = os.path.join(tmpdir, "probe.cpp")
    with open(path, "w") as fh:
        fh.write(src)
    for flag in ("-std=c++23", "-std=c++2b", "/std:c++latest"):
        if flag.startswith("/"):
            cmd = [cxx, flag, "/c", "/nologo", path]
        else:
            cmd = [cxx, flag, "-c", path, "-o", os.path.join(tmpdir, "probe.o")]
        try:
            res = subprocess.run(
                cmd,
                env=env["ENV"] if "ENV" in env else None,
                cwd=tmpdir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=60,
            )
        except Exception:
            continue
        if res.returncode == 0:
            ok = True
            break
    try:
        import shutil

        shutil.rmtree(tmpdir, ignore_errors=True)
    except Exception:
        pass

    _CXX23_CACHE[key] = ok
    return ok


def can_build(env, platform):
    if _has_std_expected(env):
        return True
    print(
        "kimodo: DISABLED - the toolchain's standard library has no <expected>, "
        "which kimodo's vendored sources require (C++23). "
        "Build with GCC 13+, clang 16+ with libc++, or MSVC 19.33+ to enable it."
    )
    return False


def configure(env):
    pass


def get_doc_classes():
    return [
        "KimodoModel",
    ]


def get_doc_path():
    return "doc_classes"
