require 'spec_helper'

RSpec.describe BasePricing do
  let(:bean1) { create(:coffee_bean, price_per_100g: 68, stock_grams: 1000) }
  let(:bean2) { create(:coffee_bean, price_per_100g: 88, stock_grams: 500) }

  describe Order::Pricing do
    describe '#calculate' do
      it 'returns correct subtotal without promo code' do
        items = [
          { 'coffee_bean_id' => bean1.id, 'quantity_grams' => 250 }
        ]
        result = described_class.new(items, nil).calculate

        expect(result).to be_valid
        expect(result.subtotal).to eq(170)
        expect(result.discount_amount).to eq(0)
        expect(result.final_total).to eq(170)
        expect(result.promotion_code).to be_nil
        expect(result.line_items.size).to eq(1)
        expect(result.line_items[0][:subtotal]).to eq(170)
      end

      it 'sums multiple items correctly' do
        items = [
          { 'coffee_bean_id' => bean1.id, 'quantity_grams' => 250 },
          { 'coffee_bean_id' => bean2.id, 'quantity_grams' => 100 }
        ]
        result = described_class.new(items, nil).calculate

        expect(result).to be_valid
        expect(result.subtotal).to eq(258)
        expect(result.final_total).to eq(258)
      end

      it 'applies fixed discount promo correctly' do
        promo = create(:promotion_code, code: 'FIXED30', discount_type: 'fixed', discount_value: 30)
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 250 }]

        result = described_class.new(items, 'FIXED30').calculate

        expect(result).to be_valid
        expect(result.subtotal).to eq(170)
        expect(result.discount_amount).to eq(30)
        expect(result.final_total).to eq(140)
        expect(result.promotion_code.id).to eq(promo.id)
      end

      it 'applies percentage discount promo correctly' do
        promo = create(:promotion_code, :percentage, code: 'PCT20', discount_value: 20)
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 250 }]

        result = described_class.new(items, 'PCT20').calculate

        expect(result).to be_valid
        expect(result.subtotal).to eq(170)
        expect(result.discount_amount).to eq(34)
        expect(result.final_total).to eq(136)
      end

      it 'caps fixed discount at subtotal' do
        promo = create(:promotion_code, code: 'BIGDISCOUNT', discount_type: 'fixed', discount_value: 500)
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'BIGDISCOUNT').calculate

        expect(result).to be_valid
        expect(result.subtotal).to eq(68)
        expect(result.discount_amount).to eq(68)
        expect(result.final_total).to eq(0)
      end

      it 'treats empty promo code string as no promo' do
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, '   ').calculate

        expect(result).to be_valid
        expect(result.discount_amount).to eq(0)
        expect(result.promotion_code).to be_nil
      end

      it 'matches promo code case-insensitively' do
        create(:promotion_code, code: 'WELCOME10', discount_type: 'fixed', discount_value: 20)
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'welcome10').calculate

        expect(result).to be_valid
        expect(result.discount_amount).to eq(20)
        expect(result.promotion_code.code).to eq('WELCOME10')
      end

      it 'returns error for non-existent promo code' do
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'NOSUCH').calculate

        expect(result).not_to be_valid
        expect(result.error).to eq('优惠码不存在')
      end

      it 'returns error for inactive promo code' do
        create(:promotion_code, :inactive, code: 'INACTIVE')
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'INACTIVE').calculate

        expect(result).not_to be_valid
        expect(result.error).to eq('优惠码已停用')
      end

      it 'returns error for expired promo code' do
        create(:promotion_code, :expired, code: 'EXPIRED')
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'EXPIRED').calculate

        expect(result).not_to be_valid
        expect(result.error).to eq('优惠码已过期')
      end

      it 'returns error for used up promo code' do
        create(:promotion_code, :used_up, code: 'USEDUP')
        items = [{ 'coffee_bean_id' => bean1.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'USEDUP').calculate

        expect(result).not_to be_valid
        expect(result.error).to eq('优惠码已用完')
      end

      it 'returns error when a bean does not exist' do
        items = [{ 'coffee_bean_id' => 999_999, 'quantity_grams' => 100 }]

        result = described_class.new(items, nil).calculate

        expect(result).not_to be_valid
        expect(result.error).to include('咖啡豆不存在或已下架')
      end

      it 'returns error for inactive bean even if promo is valid' do
        inactive_bean = create(:coffee_bean, active: false)
        promo = create(:promotion_code, code: 'GOODCODE', discount_value: 10)
        items = [{ 'coffee_bean_id' => inactive_bean.id, 'quantity_grams' => 100 }]

        result = described_class.new(items, 'GOODCODE').calculate

        expect(result).not_to be_valid
        expect(result.error).to include('咖啡豆不存在或已下架')
      end
    end
  end

  describe Subscription::Pricing do
    it 'is equivalent to Order::Pricing for the same inputs' do
      promo = create(:promotion_code, :percentage, code: 'SUBPCT', discount_value: 15)
      items = [
        { 'coffee_bean_id' => bean1.id, 'quantity_grams' => 250 },
        { 'coffee_bean_id' => bean2.id, 'quantity_grams' => 200 }
      ]

      order_result = Order::Pricing.new(items, 'SUBPCT').calculate
      sub_result = described_class.new(items, 'SUBPCT').calculate

      expect(sub_result.subtotal).to eq(order_result.subtotal)
      expect(sub_result.discount_amount).to eq(order_result.discount_amount)
      expect(sub_result.final_total).to eq(order_result.final_total)
      expect(sub_result.promotion_code.id).to eq(promo.id)
      expect(sub_result.line_items.size).to eq(2)
    end
  end
end
