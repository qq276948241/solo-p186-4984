class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :address, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending'
      t.string :order_type, null: false, default: 'one_time'
      t.decimal :total_amount, null: false, precision: 10, scale: 2
      t.datetime :delivered_at
      t.timestamps
    end
  end
end
