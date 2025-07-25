#pragma once

#include <ion/core/store/transaction_base.h>
#include <ion/core/error.h>
#include <ion/core/store/store_handle.h>
#include <expected>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
#include <toml++/toml.h>

namespace ion::core::detail {

class toml_store;

/**
 * @brief Implementation of transaction_base for TOML-based storage.
 *
 * This class provides a concrete implementation of the transaction_base interface,
 * using an in-memory representation of TOML data. It supports ACID-compliant
 * operations on hierarchical storage data.
 */
class toml_transaction final : public transaction_base {
public:
    toml_transaction(toml::table const& initial_data, toml_store* store, toml_store_options const& options);
    ~toml_transaction() noexcept override;

    std::expected<store_handle, std::error_code> root() const override;
    std::expected<bool, std::error_code> get_bool(store_handle h) const override;
    std::expected<int64_t, std::error_code> get_int(store_handle h) const override;
    std::expected<double, std::error_code> get_double(store_handle h) const override;
    std::expected<std::string, std::error_code> get_string(store_handle h) const override;
    std::expected<void, std::error_code> set_bool(store_handle h, bool v) override;
    std::expected<void, std::error_code> set_int(store_handle h, int64_t v) override;
    std::expected<void, std::error_code> set_double(store_handle h, double v) override;
    std::expected<void, std::error_code> set_string(store_handle h, std::string_view v) override;
    std::expected<store_handle, std::error_code> make_array(store_handle parent, std::string_view key) override;
    std::expected<store_handle, std::error_code> make_object(store_handle parent, std::string_view key) override;
    std::expected<void, std::error_code> make_bool(store_handle parent, std::string_view key, bool v) override;
    std::expected<void, std::error_code> make_int(store_handle parent, std::string_view key, int64_t v) override;
    std::expected<void, std::error_code> make_double(store_handle parent, std::string_view key, double v) override;
    std::expected<void, std::error_code> make_string(store_handle parent, std::string_view key, std::string_view v) override;
    std::expected<void, std::error_code> remove(store_handle parent, std::string_view key) override;
    std::expected<bool, std::error_code> has(store_handle parent, std::string_view key) const override;
    std::expected<void, std::error_code> erase_element(store_handle parent, size_t idx) override;
    std::expected<bool, std::error_code> has_element(store_handle parent, size_t idx) const override;
    std::expected<store_handle, std::error_code> child(store_handle parent, std::string_view key) const override;
    std::expected<store_handle, std::error_code> element(store_handle parent, size_t idx) const override;

private:
    std::expected<void, std::error_code> commit_impl() override;
    void rollback_impl() noexcept override;

    // node representation for handle mapping
    struct node {
        std::vector<std::string> path;  // Path from root to reconstruct node access
    };

    toml::table data_;
    toml_store* store_;
    toml_store_options options_;
    mutable std::unordered_map<uint64_t, node> handle_map_;
    mutable uint64_t next_handle_ = 1;
    
    store_handle make_handle(std::vector<std::string> path) const;
    toml::node* get_node(store_handle h);
    toml::node const* get_node(store_handle h) const;
    std::expected<toml::node*, std::error_code> get_node_checked(store_handle h);
    std::expected<toml::node const*, std::error_code> get_node_checked(store_handle h) const;
    toml::node* navigate_to_node(std::vector<std::string> const& path);
    toml::node const* navigate_to_node(std::vector<std::string> const& path) const;
    bool is_valid_key(std::string_view key) const;
};

} // namespace ion::core
