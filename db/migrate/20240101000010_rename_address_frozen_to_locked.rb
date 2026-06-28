class RenameAddressFrozenToLocked < ActiveRecord::Migration[7.1]
  def change
    rename_column :addresses, :frozen, :locked
  end
end
