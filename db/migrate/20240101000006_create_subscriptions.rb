class CreateSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :address, null: false, foreign_key: true
      t.string :frequency, null: false
      t.string :status, null: false, default: 'active'
      t.date :start_date, null: false
      t.date :next_delivery_date, null: false
      t.integer :skip_next_count, null: false, default: 0
      t.decimal :total_amount_per_delivery, null: false, precision: 10, scale: 2, default: 0
      t.timestamps
    end
  end
end
