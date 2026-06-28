class CoffeeRoasteryAPI
  get '/api/coffee_beans' do
    beans = CoffeeBean.active.order(created_at: :desc)
    { coffee_beans: serialize(beans) }.to_json
  end

  get '/api/coffee_beans/:id' do
    bean = CoffeeBean.find_by(id: params[:id])
    halt 404, { error: '咖啡豆不存在' }.to_json unless bean

    { coffee_bean: serialize(bean) }.to_json
  end

  namespace '/api/customers' do
    post '/register' do
      data = parse_request_body
      halt 400, { error: '缺少必要参数' }.to_json unless data['name'] && data['email']

      user = User.new(
        name: data['name'],
        email: data['email'],
        phone: data['phone'],
        role: 'customer'
      )

      if user.save
        status 201
        { user: serialize(user) }.to_json
      else
        status 422
        { errors: user.errors.full_messages }.to_json
      end
    end

    namespace '/me' do
      before { authenticate! }

      get do
        { user: serialize(current_user) }.to_json
      end

      namespace '/addresses' do
        get do
          addresses = current_user.addresses.order(is_default: :desc, created_at: :desc)
          { addresses: serialize(addresses) }.to_json
        end

        post do
          data = parse_request_body
          required = %w[recipient_name phone province city district detail]
          halt 400, { error: '缺少必要参数' }.to_json unless required.all? { |k| data[k].present? }

          address = current_user.addresses.new(
            recipient_name: data['recipient_name'],
            phone: data['phone'],
            province: data['province'],
            city: data['city'],
            district: data['district'],
            detail: data['detail'],
            is_default: data['is_default'] || false
          )

          if address.save
            status 201
            { address: serialize(address) }.to_json
          else
            status 422
            { errors: address.errors.full_messages }.to_json
          end
        end

        put '/:id/default' do
          address = current_user.addresses.find_by(id: params[:id])
          halt 404, { error: '地址不存在' }.to_json unless address
          halt 422, { error: '订阅已冻结该地址，无法修改' }.to_json if address.locked?

          address.update!(is_default: true)
          { address: serialize(address) }.to_json
        end

        put '/:id' do
          data = parse_request_body
          address = current_user.addresses.find_by(id: params[:id])
          halt 404, { error: '地址不存在' }.to_json unless address
          halt 422, { error: '订阅已冻结该地址，无法修改' }.to_json if address.locked?

          updatable = %w[recipient_name phone province city district detail is_default]
          update_data = data.slice(*updatable)

          if address.update(update_data)
            { address: serialize(address) }.to_json
          else
            status 422
            { errors: address.errors.full_messages }.to_json
          end
        end

        delete '/:id' do
          address = current_user.addresses.find_by(id: params[:id])
          halt 404, { error: '地址不存在' }.to_json unless address
          halt 422, { error: '订阅已冻结该地址，无法删除' }.to_json if address.locked?

          address.destroy!
          { message: '地址已删除' }.to_json
        end
      end

      namespace '/orders' do
        get do
          orders = Order.history_for(current_user)
          { orders: serialize(orders, include_items: true, include_address: true, include_promo: true) }.to_json
        end

        get '/:id' do
          order = current_user.orders.find_by(id: params[:id])
          halt 404, { error: '订单不存在' }.to_json unless order

          { order: serialize(order, include_items: true, include_address: true, include_promo: true) }.to_json
        end

        post do
          data = parse_request_body
          items_data = data['items']
          address_id = data['address_id']
          promo_code = data['promo_code']

          halt 400, { error: '缺少商品明细' }.to_json unless items_data.is_a?(Array) && items_data.any?

          address = if address_id
                      current_user.addresses.find_by(id: address_id)
                    else
                      current_user.default_address
                    end
          halt 400, { error: '请先添加收货地址' }.to_json unless address

          pricing = Order::Pricing.new(items_data, promo_code, user: current_user)
          pricing_result = pricing.calculate
          halt 422, { error: pricing_result.error }.to_json unless pricing_result.valid?

          order = nil
          ActiveRecord::Base.transaction do
            order = current_user.orders.create!(
              address: address,
              order_type: 'one_time',
              status: 'pending',
              promotion_code: pricing_result.promotion_code,
              discount_amount: pricing_result.discount_amount,
              total_amount: pricing_result.final_total
            )

            pricing_result.line_items.each do |li|
              bean = li[:coffee_bean]
              quantity = li[:quantity_grams]
              halt 400, { error: "#{bean.name} 库存不足" }.to_json if bean.stock_grams < quantity

              order.order_items.create!(
                coffee_bean: bean,
                quantity_grams: quantity,
                unit_price: li[:unit_price],
                subtotal: li[:subtotal]
              )

              bean.adjust_stock!(-quantity)
            end

            if pricing_result.promotion_code
              redemption = pricing_result.promotion_code.record_use!(
                user: current_user,
                redeemable: order
              )
              halt 422, { error: '优惠码使用失败，请重试' }.to_json unless redemption
            end
          end

          status 201
          { order: serialize(order.reload, include_items: true, include_address: true, include_promo: true) }.to_json
        end
      end

      namespace '/subscriptions' do
        get do
          subs = current_user.subscriptions.order(created_at: :desc)
          { subscriptions: serialize(subs, include_items: true, include_address: true, include_promo: true) }.to_json
        end

        get '/:id' do
          sub = current_user.subscriptions.find_by(id: params[:id])
          halt 404, { error: '订阅不存在' }.to_json unless sub

          { subscription: serialize(sub, include_items: true, include_address: true, include_promo: true) }.to_json
        end

        post do
          data = parse_request_body
          items_data = data['items']
          frequency = data['frequency']
          address_id = data['address_id']
          start_date = data['start_date'] ? Date.parse(data['start_date']) : Date.tomorrow
          promo_code = data['promo_code']

          halt 400, { error: '缺少配送频率' }.to_json unless Subscription::FREQUENCIES.key?(frequency)
          halt 400, { error: '缺少商品明细' }.to_json unless items_data.is_a?(Array) && items_data.any?

          address = if address_id
                      current_user.addresses.find_by(id: address_id)
                    else
                      current_user.default_address
                    end
          halt 400, { error: '请先添加收货地址' }.to_json unless address

          pricing = Subscription::Pricing.new(items_data, promo_code, user: current_user)
          pricing_result = pricing.calculate
          halt 422, { error: pricing_result.error }.to_json unless pricing_result.valid?

          sub = nil
          ActiveRecord::Base.transaction do
            sub = current_user.subscriptions.create!(
              address: address,
              frequency: frequency,
              status: 'active',
              start_date: start_date,
              next_delivery_date: start_date,
              promotion_code: pricing_result.promotion_code,
              discount_amount: pricing_result.discount_amount,
              total_amount_per_delivery: pricing_result.final_total
            )

            pricing_result.line_items.each do |li|
              sub.subscription_items.create!(
                coffee_bean: li[:coffee_bean],
                quantity_grams: li[:quantity_grams],
                unit_price: li[:unit_price],
                subtotal: li[:subtotal]
              )
            end

            if pricing_result.promotion_code
              redemption = pricing_result.promotion_code.record_use!(
                user: current_user,
                redeemable: sub
              )
              halt 422, { error: '优惠码使用失败，请重试' }.to_json unless redemption
            end

            sub.lock_address!
          end

          status 201
          { subscription: serialize(sub.reload, include_items: true, include_address: true, include_promo: true) }.to_json
        end

        patch '/:id/pause' do
          sub = current_user.subscriptions.find_by(id: params[:id])
          halt 404, { error: '订阅不存在' }.to_json unless sub
          halt 422, { error: '订阅当前状态不支持暂停' }.to_json unless sub.status == 'active'

          sub.pause!
          { subscription: serialize(sub) }.to_json
        end

        patch '/:id/resume' do
          sub = current_user.subscriptions.find_by(id: params[:id])
          halt 404, { error: '订阅不存在' }.to_json unless sub
          halt 422, { error: '订阅当前状态不支持恢复' }.to_json unless sub.status == 'paused'

          sub.resume!
          { subscription: serialize(sub) }.to_json
        end

        patch '/:id/skip_next' do
          sub = current_user.subscriptions.find_by(id: params[:id])
          halt 404, { error: '订阅不存在' }.to_json unless sub
          halt 422, { error: '订阅未生效' }.to_json unless sub.status == 'active'

          sub.skip_next!
          { subscription: serialize(sub) }.to_json
        end

        patch '/:id/cancel' do
          sub = current_user.subscriptions.find_by(id: params[:id])
          halt 404, { error: '订阅不存在' }.to_json unless sub

          sub.cancel!
          { subscription: serialize(sub) }.to_json
        end
      end

      post '/validate_promo_code' do
        data = parse_request_body
        code = data['code']
        order_subtotal = data['subtotal'].to_f

        promo = validate_promo_code(code)

        if promo
          discount = promo.calculate_discount(order_subtotal)
          final_total = (order_subtotal - discount).round(2)
          final_total = 0 if final_total < 0

          {
            valid: true,
            promotion_code: promotion_code_attributes(promo),
            subtotal: order_subtotal,
            discount_amount: discount,
            final_total: final_total
          }.to_json
        else
          { valid: false }.to_json
        end
      end

      get '/shipments_history' do
        shipments = Shipment.history_for_user(current_user)
        { shipments: serialize(shipments, include_address: true) }.to_json
      end
    end
  end
end
