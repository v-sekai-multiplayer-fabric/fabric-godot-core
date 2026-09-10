#include "error.hpp"

#include <algorithm>
#include <cstring>
#include <limits>

namespace motionbricks::detail {

void write_error(char * output, std::uint64_t capacity, std::string_view message) noexcept {
    if (output == nullptr || capacity == 0) return;
    const auto usable = capacity - 1;
    const auto bounded = std::min<std::uint64_t>(usable,
        static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max()));
    const auto count = std::min<std::size_t>(message.size(), static_cast<std::size_t>(bounded));
    if (count != 0) std::memcpy(output, message.data(), count);
    output[count] = '\0';
}

mb_status fail(mb_status status, char * error, std::uint64_t error_capacity,
               std::string_view message) noexcept {
    write_error(error, error_capacity, message);
    return status;
}

} // namespace motionbricks::detail
