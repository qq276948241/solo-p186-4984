class CoffeeBean < ActiveRecord::Base
  has_many :order_items, dependent: :restrict_with_error
  has_many :subscription_items, dependent: :restrict_with_error
  has_many :roast_batches, dependent: :destroy
  has_many :orders, through: :order_items

  validates :name, presence: true
  validates :origin, presence: true
  validates :roast_level, presence: true, inclusion: { in: %w[light medium medium_dark dark] }
  validates :flavor_description, presence: true
  validates :stock_grams, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_per_100g, presence: true, numericality: { greater_than: 0 }

  ROAST_LEVELS = {
    'light' => '浅烘焙',
    'medium' => '中烘焙',
    'medium_dark' => '中深烘焙',
    'dark' => '深烘焙'
  }.freeze

  scope :active, -> { where(active: true) }
  scope :in_stock, -> { where('stock_grams > 0') }

  def roast_level_display
    ROAST_LEVELS[roast_level] || roast_level
  end

  def adjust_stock!(delta_grams)
    new_stock = stock_grams + delta_grams
    raise ArgumentError, '库存不足' if new_stock < 0

    update!(stock_grams: new_stock)
  end

  def price_for(grams)
    (price_per_100g * grams / 100.0).round(2)
  end

  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end
end
