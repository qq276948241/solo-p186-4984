class Order < ActiveRecord::Base
  belongs_to :user
  belongs_to :address
  has_many :order_items, dependent: :destroy
  has_many :shipments, dependent: :nullify

  accepts_nested_attributes_for :order_items

  validates :status, presence: true, inclusion: { in: %w[pending processing shipped delivered cancelled] }
  validates :order_type, presence: true, inclusion: { in: %w[one_time subscription] }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  STATUSES = {
    'pending' => '待处理',
    'processing' => '处理中',
    'shipped' => '已发货',
    'delivered' => '已送达',
    'cancelled' => '已取消'
  }.freeze

  scope :history_for, ->(user) { where(user: user).order(created_at: :desc) }

  def status_display
    STATUSES[status] || status
  end

  def calculate_total!
    self.total_amount = order_items.sum(&:subtotal)
    save!
  end
end
