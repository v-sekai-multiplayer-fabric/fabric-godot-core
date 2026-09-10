#pragma once

#include <motionbricks/motionbricks.h>

#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace motionbricks {

class api_error final : public std::runtime_error {
public:
    api_error(mb_status status, const char * message)
        : std::runtime_error(message != nullptr ? message : mb_status_string(status)), status_(status) {}

    [[nodiscard]] mb_status status() const noexcept { return status_; }

private:
    mb_status status_;
};

class runtime_options final {
public:
    runtime_options() {
        std::array<char, 512> error{};
        const auto status = mb_runtime_options_create(&value_, error.data(), error.size());
        if (status != MB_OK) throw api_error(status, error.data());
    }

    ~runtime_options() { mb_runtime_options_free(value_); }
    runtime_options(const runtime_options &) = delete;
    runtime_options & operator=(const runtime_options &) = delete;

    runtime_options(runtime_options && other) noexcept : value_(other.value_) {
        other.value_ = nullptr;
    }

    runtime_options & operator=(runtime_options && other) noexcept {
        if (this != &other) {
            mb_runtime_options_free(value_);
            value_ = other.value_;
            other.value_ = nullptr;
        }
        return *this;
    }

    [[nodiscard]] mb_runtime_options * get() noexcept { return value_; }
    [[nodiscard]] const mb_runtime_options * get() const noexcept { return value_; }

private:
    mb_runtime_options * value_ = nullptr;
};

} // namespace motionbricks
