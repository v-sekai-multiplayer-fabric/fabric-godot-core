#pragma once

#include <motionbricks/motionbricks.h>

#include <filesystem>
#include <string>

struct mb_model;

namespace motionbricks::detail {

mb_status load_model_bundle(const std::filesystem::path & directory,
                            const mb_runtime_options * options,
                            mb_model & output, std::string & reason);

} // namespace motionbricks::detail
