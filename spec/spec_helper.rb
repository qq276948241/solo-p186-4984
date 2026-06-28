ENV['RACK_ENV'] ||= 'test'
ENV['SINATRA_ENV'] ||= 'test'

require 'rack/test'
require 'rspec'
require 'active_record'
require 'factory_bot'
require 'database_cleaner/active_record'
require 'faker'

require File.expand_path('../app', __dir__)

ActiveRecord::Base.establish_connection(
  YAML.load_file(File.expand_path('../database.yml', __dir__))['test']
)

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include FactoryBot::Syntax::Methods

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    ActiveRecord::Migration.maintain_test_schema!
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end

def app
  CoffeeRoasteryAPI
end

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    phone { Faker::PhoneNumber.phone_number }
    role { 'customer' }
  end

  factory :admin, class: User do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    phone { Faker::PhoneNumber.phone_number }
    role { 'admin' }
  end

  factory :address do
    user
    recipient_name { Faker::Name.name }
    phone { Faker::PhoneNumber.phone_number }
    province { '浙江省' }
    city { '杭州市' }
    district { '西湖区' }
    detail { Faker::Address.street_address }
    is_default { true }
    locked { false }
  end

  factory :coffee_bean do
    name { Faker::Coffee.blend_name }
    origin { Faker::Coffee.origin }
    roast_level { CoffeeBean::ROAST_LEVELS.keys.sample }
    flavor_description { Faker::Coffee.notes }
    stock_grams { 5000 }
    price_per_100g { 68 }
    active { true }
  end

  factory :order do
    user
    address
    status { 'pending' }
    order_type { 'one_time' }
    total_amount { 0 }
  end

  factory :order_item do
    order
    coffee_bean
    quantity_grams { 250 }
    unit_price { 68 }
    subtotal { 170 }
  end

  factory :subscription do
    user
    address
    frequency { 'weekly' }
    status { 'active' }
    start_date { Date.today }
    next_delivery_date { Date.tomorrow }
    skip_next_count { 0 }
    total_amount_per_delivery { 0 }
  end

  factory :subscription_item do
    subscription
    coffee_bean
    quantity_grams { 250 }
    unit_price { 68 }
    subtotal { 170 }
  end

  factory :roast_batch do
    coffee_bean
    roast_quantity_grams { 2000 }
    roasted_at { Time.current }
    notes { '测试烘焙批次' }
  end

  factory :shipment do
    roast_batch
    address
    scheduled_date { Date.today }
    status { 'pending' }
    total_weight_grams { 250 }
  end
end
