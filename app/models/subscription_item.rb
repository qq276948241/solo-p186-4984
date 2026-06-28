class SubscriptionItem < ActiveRecord::Base
  belongs_to :subscription
  belongs_to :coffee_bean

  validates :quantity_grams, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than: 0 }
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :calculate_subtotal

  private

  def calculate_subtotal
    return unless coffee_bean && quantity_grams

    self.unit_price ||= coffee_bean.price_per_100g
    self.subtotal = (unit_price * quantity_grams / 100.0).round(2)
  end
end
