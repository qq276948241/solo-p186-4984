class CreateRoastBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :roast_batches do |t|
      t.string :batch_number, null: false
      t.references :coffee_bean, null: false, foreign_key: true
      t.integer :roast_quantity_grams, null: false
      t.datetime :roasted_at, null: false
      t.text :notes
      t.timestamps
    end

    add_index :roast_batches, :batch_number, unique: true
  end
end
