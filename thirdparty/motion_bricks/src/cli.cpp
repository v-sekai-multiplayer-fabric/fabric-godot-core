#include <motionbricks/motionbricks.h>

#include <array>
#include <iostream>
#include <memory>
#include <string_view>

namespace {

struct model_deleter {
    void operator()(mb_model * value) const noexcept { mb_model_free(value); }
};

int inspect(const char * directory) {
    std::array<char, 1024> error{};
    mb_model * raw = nullptr;
    const auto status = mb_model_load(directory, nullptr, &raw, error.data(), error.size());
    std::unique_ptr<mb_model, model_deleter> model(raw);
    if (status != MB_OK) {
        std::cerr << "model load failed (" << mb_status_string(status) << "): " << error.data() << '\n';
        return 1;
    }
    std::uint64_t parameters = 0;
    std::uint32_t joints = 0;
    if (mb_model_get_parameter_count(model.get(), &parameters, error.data(), error.size()) != MB_OK ||
        mb_model_get_joint_count(model.get(), &joints, error.data(), error.size()) != MB_OK) {
        std::cerr << "model inspection failed: " << error.data() << '\n';
        return 1;
    }
    std::cout << "architecture: motionbricks\n"
              << "skeleton: g1skel34\n"
              << "parameters: " << parameters << '\n'
              << "joints: " << joints << '\n';
    for (std::uint32_t joint = 0; joint < joints; ++joint) {
        const char * name = nullptr;
        std::int32_t parent = -1;
        if (mb_model_get_joint_name(model.get(), joint, &name, error.data(), error.size()) != MB_OK ||
            mb_model_get_joint_parent(model.get(), joint, &parent, error.data(), error.size()) != MB_OK) {
            std::cerr << "joint inspection failed: " << error.data() << '\n';
            return 1;
        }
        std::cout << "joint[" << joint << "]: " << name << " parent=" << parent << '\n';
    }
    return 0;
}

} // namespace

int main(int argc, char ** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "abi") {
        std::cout << "motion-bricks.cpp ABI " << mb_abi_version() << '\n';
        return 0;
    }
    if (argc == 3 && std::string_view(argv[1]) == "inspect") return inspect(argv[2]);

    std::cerr << "usage: motionbricks-cli abi | inspect BUNDLE_DIRECTORY\n";
    return 2;
}
