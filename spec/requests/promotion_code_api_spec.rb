require 'spec_helper'

RSpec.describe 'Promotion Code API', type: :request do
  let(:customer) { create(:user) }
  let(:admin) { create(:admin) }
  let(:address) { create(:address, user: customer) }
  let(:bean) { create(:coffee_bean, price_per_100g: 68, stock_grams: 1000) }
  let(:headers) { { 'HTTP_X_USER_ID' => customer.id, 'CONTENT_TYPE' => 'application/json' } }
  let(:admin_headers) { { 'HTTP_X_USER_ID' => admin.id, 'CONTENT_TYPE' => 'application/json' } }

  describe 'POST /api/customers/me/validate_promo_code' do
    it 'validates a working promo code and returns discount' do
      create(:promotion_code, code: 'WELCOME10', discount_type: 'fixed', discount_value: 30)
      post '/api/customers/me/validate_promo_code',
        { code: 'WELCOME10', subtotal: 200 }.to_json, headers

      expect(last_response).to be_successful
      json = JSON.parse(last_response.body)
      expect(json['valid']).to be true
      expect(json['discount_amount']).to eq(30)
      expect(json['final_total']).to eq(170)
      expect(json['promotion_code']['code']).to eq('WELCOME10')
    end

    it 'handles case-insensitive code' do
      create(:promotion_code, code: 'WELCOME10', discount_type: 'fixed', discount_value: 30)
      post '/api/customers/me/validate_promo_code',
        { code: 'welcome10', subtotal: 200 }.to_json, headers

      expect(last_response).to be_successful
      json = JSON.parse(last_response.body)
      expect(json['valid']).to be true
    end

    it 'returns error for non-existent code' do
      post '/api/customers/me/validate_promo_code',
        { code: 'INVALID', subtotal: 200 }.to_json, headers

      expect(last_response.status).to eq(422)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('优惠码不存在')
    end

    it 'returns error for expired code' do
      create(:promotion_code, :expired, code: 'EXPIRED')
      post '/api/customers/me/validate_promo_code',
        { code: 'EXPIRED', subtotal: 200 }.to_json, headers

      expect(last_response.status).to eq(422)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('优惠码已过期')
    end

    it 'returns error for used up code' do
      create(:promotion_code, :used_up, code: 'USEDMY')
      post '/api/customers/me/validate_promo_code',
        { code: 'USEDMY', subtotal: 200 }.to_json, headers

      expect(last_response.status).to eq(422)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('优惠码已用完')
    end

    it 'returns error for inactive code' do
      create(:promotion_code, :inactive, code: 'INACTIVE')
      post '/api/customers/me/validate_promo_code',
        { code: 'INACTIVE', subtotal: 200 }.to_json, headers

      expect(last_response.status).to eq(422)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('优惠码已停用')
    end
  end

  describe 'POST /api/customers/me/orders with promo code' do
    let(:order_params) do
      {
        items: [{ coffee_bean_id: bean.id, quantity_grams: 250 }],
        address_id: address.id
      }
    end

    context 'with valid promo code' do
      let!(:promo) { create(:promotion_code, code: 'ORDER30', discount_type: 'fixed', discount_value: 30, max_uses: 5) }

      it 'applies discount, attaches promo code, and records use' do
        post '/api/customers/me/orders',
          order_params.merge(promo_code: 'ORDER30').to_json, headers

        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['order']['subtotal']).to eq(170)
        expect(json['order']['discount_amount']).to eq(30)
        expect(json['order']['total_amount']).to eq(140)
        expect(json['order']['promotion_code']['code']).to eq('ORDER30')
        expect(promo.reload.used_count).to eq(1)
      end
    end

    context 'with expired promo code' do
      before { create(:promotion_code, :expired, code: 'EXPIRED') }

      it 'rejects the order with error and rolls back everything' do
        expect {
          post '/api/customers/me/orders',
            order_params.merge(promo_code: 'EXPIRED').to_json, headers
        }.not_to change(Order, :count)

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        expect(json['error']).to eq('优惠码已过期')
        expect(bean.reload.stock_grams).to eq(1000)
      end
    end

    context 'without promo code' do
      it 'creates order without discount' do
        post '/api/customers/me/orders', order_params.to_json, headers

        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['order']['subtotal']).to eq(170)
        expect(json['order']['discount_amount']).to eq(0)
        expect(json['order']['total_amount']).to eq(170)
        expect(json['order']['promotion_code']).to be_nil
      end
    end
  end

  describe 'POST /api/customers/me/subscriptions with promo code' do
    let(:sub_params) do
      {
        items: [{ coffee_bean_id: bean.id, quantity_grams: 250 }],
        frequency: 'weekly',
        address_id: address.id,
        start_date: Date.tomorrow.to_s
      }
    end

    context 'with valid promo code' do
      let!(:promo) { create(:promotion_code, code: 'SUB50', discount_type: 'fixed', discount_value: 50, max_uses: 10) }

      it 'applies discount, attaches promo, and records use' do
        post '/api/customers/me/subscriptions',
          sub_params.merge(promo_code: 'SUB50').to_json, headers

        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['subscription']['subtotal']).to eq(170)
        expect(json['subscription']['discount_amount']).to eq(50)
        expect(json['subscription']['total_amount_per_delivery']).to eq(120)
        expect(json['subscription']['promotion_code']['code']).to eq('SUB50')
        expect(promo.reload.used_count).to eq(1)
        expect(address.reload.locked?).to be true
      end
    end

    context 'with invalid promo code' do
      before { create(:promotion_code, :expired, code: 'SUBEXPIRED') }

      it 'rejects with error and does not create subscription' do
        expect {
          post '/api/customers/me/subscriptions',
            sub_params.merge(promo_code: 'SUBEXPIRED').to_json, headers
        }.not_to change(Subscription, :count)

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        expect(json['error']).to eq('优惠码已过期')
        expect(address.reload.locked?).to be false
      end
    end
  end

  describe 'Admin promo code management' do
    describe 'POST /api/admin/promotion_codes' do
      it 'creates a fixed amount promo code' do
        post '/api/admin/promotion_codes',
          { code: 'NEWCODE1', discount_type: 'fixed', discount_value: 25, max_uses: 50 }.to_json,
          admin_headers

        expect(last_response.status).to eq(201)
        json = JSON.parse(last_response.body)
        expect(json['promotion_code']['code']).to eq('NEWCODE1')
        expect(json['promotion_code']['discount_value']).to eq(25)
      end

      it 'creates a percentage promo code' do
        post '/api/admin/promotion_codes',
          { code: 'PERCENT15', discount_type: 'percentage', discount_value: 15 }.to_json,
          admin_headers

        expect(last_response.status).to eq(201)
        json = JSON.parse(last_response.body)
        expect(json['promotion_code']['discount_type']).to eq('percentage')
      end

      it 'upcases the code before saving' do
        post '/api/admin/promotion_codes',
          { code: 'lowercase', discount_type: 'fixed', discount_value: 10 }.to_json,
          admin_headers

        expect(last_response.status).to eq(201)
        expect(PromotionCode.last.code).to eq('LOWERCASE')
      end
    end

    describe 'GET /api/admin/promotion_codes' do
      before do
        create(:promotion_code, code: 'CODE1')
        create(:promotion_code, :expired, code: 'CODE2')
      end

      it 'lists all promotion codes' do
        get '/api/admin/promotion_codes', {}, admin_headers
        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['promotion_codes'].size).to eq(2)
      end
    end

    describe 'GET /api/admin/promotion_codes/valid' do
      before do
        create(:promotion_code, code: 'VALID1')
        create(:promotion_code, :expired, code: 'EXPIRED1')
      end

      it 'lists only valid codes' do
        get '/api/admin/promotion_codes/valid', {}, admin_headers
        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['promotion_codes'].size).to eq(1)
        expect(json['promotion_codes'][0]['code']).to eq('VALID1')
      end
    end

    describe 'GET /api/admin/promotion_codes/:id' do
      it 'shows usage stats' do
        promo = create(:promotion_code, code: 'STATS1', max_uses: 10, used_count: 3)
        create_list(:order, 2, promotion_code: promo, user: customer, address: address)

        get "/api/admin/promotion_codes/#{promo.id}", {}, admin_headers
        expect(last_response).to be_successful
        json = JSON.parse(last_response.body)
        expect(json['promotion_code']['used_count']).to eq(3)
        expect(json['promotion_code']['uses_remaining']).to eq(7)
        expect(json['promotion_code']['orders_count']).to eq(2)
      end
    end

    describe 'PATCH /api/admin/promotion_codes/:id/deactivate' do
      it 'deactivates the code' do
        promo = create(:promotion_code, code: 'DEACTIVATE', active: true)
        patch "/api/admin/promotion_codes/#{promo.id}/deactivate", {}, admin_headers

        expect(last_response).to be_successful
        expect(promo.reload.active?).to be false
      end
    end

    describe 'PATCH /api/admin/promotion_codes/:id/activate' do
      it 'activates the code' do
        promo = create(:promotion_code, :inactive, code: 'ACTIVATE')
        patch "/api/admin/promotion_codes/#{promo.id}/activate", {}, admin_headers

        expect(last_response).to be_successful
        expect(promo.reload.active?).to be true
      end
    end
  end
end
