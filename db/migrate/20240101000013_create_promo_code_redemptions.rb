class CreatePromoCodeRedemptions < ActiveRecord::Migration[7.2]
  def change
    create_table :promo_code_redemptions do |t|
      t.integer :promotion_code_id, null: false
      t.integer :user_id, null: false
      t.integer :order_id
      t.integer :subscription_id
      t.datetime :redeemed_at, null: false

      t.timestamps null: false
    end

    add_index :promo_code_redemptions, [:promotion_code_id, :user_id], unique: true
    add_index :promo_code_redemptions, :user_id
    add_index :promo_code_redemptions, :order_id, unique: true
    add_index :promo_code_redemptions, :subscription_id, unique: true

    add_foreign_key :promo_code_redemptions, :promotion_codes
    add_foreign_key :promo_code_redemptions, :users
    add_foreign_key :promo_code_redemptions, :orders
    add_foreign_key :promo_code_redemptions, :subscriptions
  end
end
