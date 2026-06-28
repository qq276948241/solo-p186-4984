# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2024_01_01_000012) do
  create_table "addresses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "recipient_name", null: false
    t.string "phone", null: false
    t.string "province", null: false
    t.string "city", null: false
    t.string "district", null: false
    t.text "detail", null: false
    t.boolean "is_default", default: false, null: false
    t.boolean "locked", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_addresses_on_user_id"
  end

  create_table "coffee_beans", force: :cascade do |t|
    t.string "name", null: false
    t.string "origin", null: false
    t.string "roast_level", null: false
    t.text "flavor_description", null: false
    t.integer "stock_grams", default: 0, null: false
    t.decimal "price_per_100g", precision: 10, scale: 2, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "order_items", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "coffee_bean_id", null: false
    t.integer "quantity_grams", null: false
    t.decimal "unit_price", precision: 10, scale: 2, null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coffee_bean_id"], name: "index_order_items_on_coffee_bean_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "address_id", null: false
    t.string "status", default: "pending", null: false
    t.string "order_type", default: "one_time", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "promotion_code_id"
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["address_id"], name: "index_orders_on_address_id"
    t.index ["promotion_code_id"], name: "index_orders_on_promotion_code_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "promotion_codes", force: :cascade do |t|
    t.string "code", null: false
    t.string "discount_type", null: false
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.datetime "expires_at"
    t.integer "max_uses", default: 1, null: false
    t.integer "used_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_promotion_codes_on_code", unique: true
  end

  create_table "roast_batches", force: :cascade do |t|
    t.string "batch_number", null: false
    t.integer "coffee_bean_id", null: false
    t.integer "roast_quantity_grams", null: false
    t.datetime "roasted_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_number"], name: "index_roast_batches_on_batch_number", unique: true
    t.index ["coffee_bean_id"], name: "index_roast_batches_on_coffee_bean_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.integer "roast_batch_id", null: false
    t.integer "subscription_id"
    t.integer "order_id"
    t.integer "address_id", null: false
    t.string "status", default: "pending", null: false
    t.date "scheduled_date", null: false
    t.datetime "shipped_at"
    t.datetime "delivered_at"
    t.decimal "total_weight_grams", default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address_id"], name: "index_shipments_on_address_id"
    t.index ["order_id"], name: "index_shipments_on_order_id"
    t.index ["roast_batch_id"], name: "index_shipments_on_roast_batch_id"
    t.index ["subscription_id"], name: "index_shipments_on_subscription_id"
  end

  create_table "subscription_items", force: :cascade do |t|
    t.integer "subscription_id", null: false
    t.integer "coffee_bean_id", null: false
    t.integer "quantity_grams", null: false
    t.decimal "unit_price", precision: 10, scale: 2, null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coffee_bean_id"], name: "index_subscription_items_on_coffee_bean_id"
    t.index ["subscription_id"], name: "index_subscription_items_on_subscription_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "address_id", null: false
    t.string "frequency", null: false
    t.string "status", default: "active", null: false
    t.date "start_date", null: false
    t.date "next_delivery_date", null: false
    t.integer "skip_next_count", default: 0, null: false
    t.decimal "total_amount_per_delivery", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "promotion_code_id"
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["address_id"], name: "index_subscriptions_on_address_id"
    t.index ["promotion_code_id"], name: "index_subscriptions_on_promotion_code_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "role", default: "customer", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "addresses", "users"
  add_foreign_key "order_items", "coffee_beans"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "addresses"
  add_foreign_key "orders", "promotion_codes"
  add_foreign_key "orders", "users"
  add_foreign_key "roast_batches", "coffee_beans"
  add_foreign_key "shipments", "addresses"
  add_foreign_key "shipments", "orders"
  add_foreign_key "shipments", "roast_batches"
  add_foreign_key "shipments", "subscriptions"
  add_foreign_key "subscription_items", "coffee_beans"
  add_foreign_key "subscription_items", "subscriptions"
  add_foreign_key "subscriptions", "addresses"
  add_foreign_key "subscriptions", "promotion_codes"
  add_foreign_key "subscriptions", "users"
end
