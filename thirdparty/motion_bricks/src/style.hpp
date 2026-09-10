#pragma once

#include <motionbricks/motionbricks.h>

#include <filesystem>
#include <string>

struct mb_style;

namespace motionbricks::detail {

mb_status load_style_file(const std::filesystem::path & path,
                          mb_style & output, std::string & reason);

} // namespace motionbricks::detail
