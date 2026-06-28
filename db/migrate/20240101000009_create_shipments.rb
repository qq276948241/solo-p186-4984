class CreateShipments < ActiveRecord::Migration[7.1]
  def change
    create_table :shipments do |t|
      t.references :roast_batch, null: false, foreign_key: true
      t.references :subscription, foreign_key: true
      t.references :order, foreign_key: true
      t.references :address, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending'
      t.date :scheduled_date, null: false
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.decimal :total_weight_grams, null: false, default: 0
      t.timestamps
    end
  end
end
