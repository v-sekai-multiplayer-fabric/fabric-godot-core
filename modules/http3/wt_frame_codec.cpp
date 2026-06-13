// Compiles the webtransportd frame codec (thirdparty/webtransportd/frame.c) as a
// single translation unit owned by this module's env, avoiding the "two
// environments for the same target" scons conflict that arises from adding the
// thirdparty .c directly. frame.c is pure C (stddef/stdint only); its declarations
// in frame.h are `extern "C"`, so wrap the definitions to match that linkage.
extern "C" {
#include "frame.c"
}
