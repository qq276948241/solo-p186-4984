class CreateAddresses < ActiveRecord::Migration[7.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :recipient_name, null: false
      t.string :phone, null: false
      t.string :province, null: false
      t.string :city, null: false
      t.string :district, null: false
      t.text :detail, null: false
      t.boolean :is_default, null: false, default: false
      t.boolean :frozen, null: false, default: false
      t.timestamps
    end
  end
end
