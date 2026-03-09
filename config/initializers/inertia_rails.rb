# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = ViteRuby.digest
  config.encrypt_history = true
  config.always_include_errors_hash = true
  config.ssr_enabled = ViteRuby.config.ssr_build_enabled
  config.use_script_element_for_initial_page = true
  config.use_data_inertia_head_attribute = true

  # Transform snake_case props to camelCase for JavaScript frontend
  config.prop_transformer = lambda do |props:|
    props.deep_transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
