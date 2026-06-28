class BasePricing
  Result = Struct.new(
    :subtotal, :discount_amount, :final_total,
    :promotion_code, :line_items, :error,
    keyword_init: true
  ) do
    def valid?
      error.nil?
    end
  end

  attr_reader :result

  def initialize(items_data, promo_code_str, user: nil)
    @items_data = items_data || []
    @promo_code_str = promo_code_str
    @user = user
  end

  def calculate
    subtotal = 0.0
    line_items = []
    error = nil
    promotion_code = nil
    discount_amount = 0.0

    @items_data.each do |item_data|
      bean = CoffeeBean.active.find_by(id: item_data['coffee_bean_id'])
      unless bean
        error = "咖啡豆不存在或已下架: #{item_data['coffee_bean_id']}"
        break
      end

      quantity = item_data['quantity_grams'].to_i
      unit_price = bean.price_per_100g.to_f
      item_subtotal = (unit_price * quantity / 100.0).round(2)

      line_items << {
        coffee_bean: bean,
        quantity_grams: quantity,
        unit_price: unit_price,
        subtotal: item_subtotal
      }

      subtotal += item_subtotal
    end

    unless error
      promo, promo_error = PromotionCode.lookup_and_validate(
        @promo_code_str,
        user_id: @user&.id
      )
      if promo_error
        error = promo_error
      elsif promo
        promotion_code = promo
        discount_amount = promo.calculate_discount(subtotal)
      end
    end

    final_total = if error
                    0.0
                  else
                    (subtotal - discount_amount).round(2).tap { |v| v < 0 ? 0.0 : v }
                  end

    @result = Result.new(
      subtotal: subtotal.round(2),
      discount_amount: discount_amount.round(2),
      final_total: final_total,
      promotion_code: promotion_code,
      line_items: line_items,
      error: error
    )
  end
end
