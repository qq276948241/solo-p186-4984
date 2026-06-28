class CreatePromotionCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :promotion_codes do |t|
      t.string :code, null: false
      t.string :discount_type, null: false
      t.decimal :discount_value, null: false, precision: 10, scale: 2
      t.datetime :expires_at
      t.integer :max_uses, null: false, default: 1
      t.integer :used_count, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.text :description
      t.timestamps
    end

    add_index :promotion_codes, :code, unique: true
  end
end
