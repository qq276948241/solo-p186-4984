require 'spec_helper'

RSpec.describe PromotionCode, type: :model do
  describe 'validations' do
    it 'requires a code' do
      promo = build(:promotion_code, code: nil)
      expect(promo).not_to be_valid
    end

    it 'requires a unique code' do
      create(:promotion_code, code: 'WELCOME10')
      promo = build(:promotion_code, code: 'welcome10')
      expect(promo).not_to be_valid
    end

    it 'requires discount_type' do
      promo = build(:promotion_code, discount_type: nil)
      expect(promo).not_to be_valid
    end

    it 'validates discount_type inclusion' do
      promo = build(:promotion_code, discount_type: 'invalid')
      expect(promo).not_to be_valid
    end

    it 'requires discount_value' do
      promo = build(:promotion_code, discount_value: nil)
      expect(promo).not_to be_valid
    end

    it 'validates discount_value > 0' do
      promo = build(:promotion_code, discount_value: 0)
      expect(promo).not_to be_valid
    end

    it 'requires max_uses' do
      promo = build(:promotion_code, max_uses: nil)
      expect(promo).not_to be_valid
    end

    it 'validates max_uses >= 1' do
      promo = build(:promotion_code, max_uses: 0)
      expect(promo).not_to be_valid
    end

    it 'validates used_count >= 0' do
      promo = build(:promotion_code, used_count: -1)
      expect(promo).not_to be_valid
    end
  end

  describe '#valid_for_use?' do
    it 'returns true for an active, non-expired code with uses remaining' do
      promo = create(:promotion_code)
      expect(promo.valid_for_use?).to be true
    end

    it 'returns false for an inactive code' do
      promo = create(:promotion_code, :inactive)
      expect(promo.valid_for_use?).to be false
    end

    it 'returns false for an expired code' do
      promo = create(:promotion_code, :expired)
      expect(promo.valid_for_use?).to be false
    end

    it 'returns false for a code with no uses remaining' do
      promo = create(:promotion_code, :used_up)
      expect(promo.valid_for_use?).to be false
    end
  end

  describe '#expired?' do
    it 'returns true if expired' do
      promo = create(:promotion_code, :expired)
      expect(promo.expired?).to be true
    end

    it 'returns false if not expired' do
      promo = create(:promotion_code)
      expect(promo.expired?).to be false
    end

    it 'returns false if no expiry is set' do
      promo = create(:promotion_code, expires_at: nil)
      expect(promo.expired?).to be false
    end
  end

  describe '#used_up?' do
    it 'returns true if used count equals max uses' do
      promo = create(:promotion_code, max_uses: 5, used_count: 5)
      expect(promo.used_up?).to be true
    end

    it 'returns false if uses remaining' do
      promo = create(:promotion_code, max_uses: 5, used_count: 4)
      expect(promo.used_up?).to be false
    end
  end

  describe '#calculate_discount' do
    context 'with fixed discount' do
      let(:promo) { create(:promotion_code, discount_type: 'fixed', discount_value: 30) }

      it 'returns the fixed discount amount' do
        expect(promo.calculate_discount(100)).to eq(30)
      end

      it 'caps discount at original total' do
        expect(promo.calculate_discount(20)).to eq(20)
      end

      it 'returns 0 for invalid code' do
        promo = create(:promotion_code, :expired)
        expect(promo.calculate_discount(100)).to eq(0)
      end
    end

    context 'with percentage discount' do
      let(:promo) { create(:promotion_code, :percentage, discount_value: 20) }

      it 'returns the percentage discount' do
        expect(promo.calculate_discount(100)).to eq(20)
        expect(promo.calculate_discount(200)).to eq(40)
      end
    end
  end

  describe '#apply_to' do
    let(:promo) { create(:promotion_code, discount_type: 'fixed', discount_value: 30) }

    it 'returns final total and discount' do
      final_total, discount = promo.apply_to(100)
      expect(final_total).to eq(70)
      expect(discount).to eq(30)
    end

    it 'returns 0 if discount exceeds total' do
      final_total, discount = promo.apply_to(20)
      expect(final_total).to eq(0)
      expect(discount).to eq(20)
    end
  end

  describe '#record_use!' do
    let(:user) { create(:user) }
    let(:promo) { create(:promotion_code, max_uses: 10, used_count: 0) }

    it 'increments used_count' do
      promo.record_use!(user: user)
      expect(promo.reload.used_count).to eq(1)
    end

    it 'returns the redemption record on success' do
      redemption = promo.record_use!(user: user)
      expect(redemption).to be_a(PromoCodeRedemption)
      expect(redemption.user_id).to eq(user.id)
      expect(redemption.promotion_code_id).to eq(promo.id)
      expect(redemption.redeemed_at).to be_present
    end

    it 'returns false if code is not valid for use' do
      used_up_promo = create(:promotion_code, :used_up)
      expect(used_up_promo.record_use!(user: user)).to be false
    end

    it 'returns false if user already redeemed the code' do
      promo.record_use!(user: user)
      expect(promo.record_use!(user: user)).to be false
      expect(promo.reload.used_count).to eq(1)
    end

    it 'associates redemption with order when provided' do
      order = create(:order, user: user)
      redemption = promo.record_use!(user: user, redeemable: order)
      expect(redemption.order_id).to eq(order.id)
      expect(redemption.subscription_id).to be_nil
    end

    it 'associates redemption with subscription when provided' do
      sub = create(:subscription, user: user)
      redemption = promo.record_use!(user: user, redeemable: sub)
      expect(redemption.subscription_id).to eq(sub.id)
      expect(redemption.order_id).to be_nil
    end

    it 'prevents concurrent uses from exceeding max_uses' do
      promo = create(:promotion_code, code: 'CONCURRENT', max_uses: 2, used_count: 0)
      user2 = create(:user)
      user3 = create(:user)
      users = [user, user2, user3, user, user2, user3]

      results = users.map do |u|
        promo.record_use!(user: u)
      end

      success_count = results.count { |r| r.is_a?(PromoCodeRedemption) }
      expect(success_count).to eq(2)
      expect(promo.reload.used_count).to eq(2)
    end
  end

  describe '#uses_remaining' do
    it 'returns correct remaining uses' do
      promo = create(:promotion_code, max_uses: 10, used_count: 3)
      expect(promo.uses_remaining).to eq(7)
    end
  end

  describe '#discount_description' do
    it 'returns fixed amount description' do
      promo = create(:promotion_code, discount_type: 'fixed', discount_value: 30)
      expect(promo.discount_description).to eq('减 ¥30.0')
    end

    it 'returns percentage description' do
      promo = create(:promotion_code, :percentage, discount_value: 20)
      expect(promo.discount_description).to eq('打 8.0 折')
    end
  end

  describe 'scopes' do
    let!(:active_valid) { create(:promotion_code) }
    let!(:inactive) { create(:promotion_code, :inactive) }
    let!(:expired) { create(:promotion_code, :expired) }
    let!(:used_up) { create(:promotion_code, :used_up) }

    it '.active returns only active codes' do
      expect(described_class.active).to include(active_valid, expired, used_up)
      expect(described_class.active).not_to include(inactive)
    end

    it '.not_expired returns non-expired codes' do
      expect(described_class.not_expired).to include(active_valid, inactive, used_up)
      expect(described_class.not_expired).not_to include(expired)
    end

    it '.with_uses_remaining returns codes with uses left' do
      expect(described_class.with_uses_remaining).to include(active_valid, inactive, expired)
      expect(described_class.with_uses_remaining).not_to include(used_up)
    end

    it '.valid_now returns only valid codes' do
      expect(described_class.valid_now).to include(active_valid)
      expect(described_class.valid_now).not_to include(inactive, expired, used_up)
    end
  end
end
