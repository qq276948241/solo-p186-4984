class CreateCoffeeBeans < ActiveRecord::Migration[7.1]
  def change
    create_table :coffee_beans do |t|
      t.string :name, null: false
      t.string :origin, null: false
      t.string :roast_level, null: false
      t.text :flavor_description, null: false
      t.integer :stock_grams, null: false, default: 0
      t.decimal :price_per_100g, null: false, precision: 10, scale: 2
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end
