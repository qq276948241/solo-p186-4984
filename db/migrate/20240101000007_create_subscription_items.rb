class CreateSubscriptionItems < ActiveRecord::Migration[7.1]
  def change
    create_table :subscription_items do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :coffee_bean, null: false, foreign_key: true
      t.integer :quantity_grams, null: false
      t.decimal :unit_price, null: false, precision: 10, scale: 2
      t.decimal :subtotal, null: false, precision: 10, scale: 2
      t.timestamps
    end
  end
end
