class RoastBatch < ActiveRecord::Base
  belongs_to :coffee_bean
  has_many :shipments, dependent: :nullify

  validates :batch_number, presence: true, uniqueness: true
  validates :roast_quantity_grams, presence: true, numericality: { greater_than: 0 }
  validates :roasted_at, presence: true

  before_validation :generate_batch_number, on: :create
  after_create :add_to_stock

  def self.generate_batch_number_for(coffee_bean)
    date_str = Date.today.strftime('%Y%m%d')
    prefix = "RB#{date_str}#{coffee_bean.id}"
    last_batch = where('batch_number LIKE ?', "#{prefix}%").order(batch_number: :desc).first
    seq = last_batch ? (last_batch.batch_number.split('-').last.to_i + 1) : 1
    "#{prefix}-#{seq.to_s.rjust(3, '0')}"
  end

  private

  def generate_batch_number
    self.batch_number ||= self.class.generate_batch_number_for(coffee_bean)
  end

  def add_to_stock
    coffee_bean.adjust_stock!(roast_quantity_grams)
  end
end
