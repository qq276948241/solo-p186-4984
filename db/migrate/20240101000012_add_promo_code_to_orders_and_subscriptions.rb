class AddPromoCodeToOrdersAndSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_reference :orders, :promotion_code, foreign_key: true
    add_column :orders, :discount_amount, :decimal, precision: 10, scale: 2, default: 0, null: false

    add_reference :subscriptions, :promotion_code, foreign_key: true
    add_column :subscriptions, :discount_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
