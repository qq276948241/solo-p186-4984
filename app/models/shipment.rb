class Shipment < ActiveRecord::Base
  belongs_to :roast_batch
  belongs_to :subscription, optional: true
  belongs_to :order, optional: true
  belongs_to :address

  validates :status, presence: true, inclusion: { in: %w[pending shipped delivered cancelled] }
  validates :scheduled_date, presence: true
  validates :total_weight_grams, numericality: { greater_than_or_equal_to: 0 }

  STATUSES = {
    'pending' => '待发货',
    'shipped' => '已发货',
    'delivered' => '已送达',
    'cancelled' => '已取消'
  }.freeze

  scope :for_batch, ->(batch) { where(roast_batch: batch) }
  scope :for_user, ->(user) {
    joins(:subscription, :order)
      .where('subscriptions.user_id = ? OR orders.user_id = ?', user.id, user.id)
      .order(scheduled_date: :desc)
  }
  scope :pending, -> { where(status: 'pending') }
  scope :for_date, ->(date) { where(scheduled_date: date) }

  def status_display
    STATUSES[status] || status
  end

  def mark_shipped!
    update!(status: 'shipped', shipped_at: Time.current)
    if order
      order.update!(status: 'shipped')
    end
  end

  def mark_delivered!
    update!(status: 'delivered', delivered_at: Time.current)
    if order
      order.update!(status: 'delivered', delivered_at: Time.current)
    end
  end

  def cancel!
    update!(status: 'cancelled')
  end

  def recipient_name
    address.recipient_name
  end

  def shipping_address
    address.full_address
  end

  def self.history_for_user(user)
    includes(subscription: :user, order: :user)
      .where('subscriptions.user_id = ? OR orders.user_id = ?', user.id, user.id)
      .where.not(status: 'cancelled')
      .order(scheduled_date: :desc)
  end
end
