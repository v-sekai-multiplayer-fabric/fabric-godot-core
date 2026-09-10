#pragma once

#include <motionbricks/motionbricks.h>

#include <cstdint>
#include <exception>
#include <new>
#include <string_view>

namespace motionbricks::detail {

void write_error(char * output, std::uint64_t capacity, std::string_view message) noexcept;

template <class Function>
mb_status guard(char * error, std::uint64_t error_capacity, Function && function) noexcept {
    try {
        write_error(error, error_capacity, {});
        return function();
    } catch (const std::bad_alloc &) {
        write_error(error, error_capacity, "allocation failed");
        return MB_OUT_OF_MEMORY;
    } catch (const std::exception & exception) {
        write_error(error, error_capacity, exception.what());
        return MB_INTERNAL_ERROR;
    } catch (...) {
        write_error(error, error_capacity, "unknown internal error");
        return MB_INTERNAL_ERROR;
    }
}

mb_status fail(mb_status status, char * error, std::uint64_t error_capacity,
               std::string_view message) noexcept;

} // namespace motionbricks::detail
