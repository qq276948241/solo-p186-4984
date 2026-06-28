class CoffeeRoasteryAPI
  namespace '/api/admin' do
    before { require_admin! }

    namespace '/coffee_beans' do
      get do
        beans = CoffeeBean.order(created_at: :desc)
        { coffee_beans: serialize(beans) }.to_json
      end

      get '/:id' do
        bean = CoffeeBean.find_by(id: params[:id])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        { coffee_bean: serialize(bean) }.to_json
      end

      post do
        data = parse_request_body
        required = %w[name origin roast_level flavor_description price_per_100g]
        halt 400, { error: '缺少必要参数' }.to_json unless required.all? { |k| data[k].present? }

        bean = CoffeeBean.new(
          name: data['name'],
          origin: data['origin'],
          roast_level: data['roast_level'],
          flavor_description: data['flavor_description'],
          stock_grams: data['stock_grams'] || 0,
          price_per_100g: data['price_per_100g'],
          active: data.fetch('active', true)
        )

        if bean.save
          status 201
          { coffee_bean: serialize(bean) }.to_json
        else
          status 422
          { errors: bean.errors.full_messages }.to_json
        end
      end

      put '/:id' do
        data = parse_request_body
        bean = CoffeeBean.find_by(id: params[:id])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        updatable = %w[name origin roast_level flavor_description price_per_100g active]
        update_data = data.slice(*updatable)

        if bean.update(update_data)
          { coffee_bean: serialize(bean) }.to_json
        else
          status 422
          { errors: bean.errors.full_messages }.to_json
        end
      end

      patch '/:id/adjust_stock' do
        data = parse_request_body
        bean = CoffeeBean.find_by(id: params[:id])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        delta = data['delta_grams'].to_i
        halt 400, { error: '调整数量不能为空' }.to_json if delta.zero?

        begin
          bean.adjust_stock!(delta)
          {
            coffee_bean: serialize(bean),
            adjustment: delta,
            message: delta > 0 ? "库存增加 #{delta}g" : "库存减少 #{delta.abs}g"
          }.to_json
        rescue ArgumentError => e
          status 422
          { error: e.message }.to_json
        end
      end

      patch '/:id/activate' do
        bean = CoffeeBean.find_by(id: params[:id])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        bean.activate!
        { coffee_bean: serialize(bean) }.to_json
      end

      patch '/:id/deactivate' do
        bean = CoffeeBean.find_by(id: params[:id])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        bean.deactivate!
        { coffee_bean: serialize(bean) }.to_json
      end
    end

    namespace '/roast_batches' do
      get do
        batches = RoastBatch.order(roasted_at: :desc)
        { roast_batches: serialize(batches) }.to_json
      end

      get '/:id' do
        batch = RoastBatch.find_by(id: params[:id])
        halt 404, { error: '烘焙批次不存在' }.to_json unless batch

        { roast_batch: serialize(batch, include_shipments: true) }.to_json
      end

      post do
        data = parse_request_body
        required = %w[coffee_bean_id roast_quantity_grams]
        halt 400, { error: '缺少必要参数' }.to_json unless required.all? { |k| data[k].present? }

        bean = CoffeeBean.find_by(id: data['coffee_bean_id'])
        halt 404, { error: '咖啡豆不存在' }.to_json unless bean

        batch = RoastBatch.new(
          coffee_bean: bean,
          roast_quantity_grams: data['roast_quantity_grams'].to_i,
          roasted_at: data['roasted_at'] ? Time.parse(data['roasted_at']) : Time.current,
          notes: data['notes']
        )

        if batch.save
          status 201
          { roast_batch: serialize(batch) }.to_json
        else
          status 422
          { errors: batch.errors.full_messages }.to_json
        end
      end
    end

    namespace '/shipments' do
      get do
        scope = Shipment.order(scheduled_date: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(scheduled_date: params[:scheduled_date]) if params[:scheduled_date].present?

        { shipments: serialize(scope, include_address: true) }.to_json
      end

      get '/:id' do
        shipment = Shipment.find_by(id: params[:id])
        halt 404, { error: '配送单不存在' }.to_json unless shipment

        { shipment: serialize(shipment, include_address: true) }.to_json
      end

      post '/generate_from_subscriptions' do
        data = parse_request_body
        roast_batch_id = data['roast_batch_id']
        delivery_date = data['delivery_date'] ? Date.parse(data['delivery_date']) : Date.today

        roast_batch = RoastBatch.find_by(id: roast_batch_id)
        halt 404, { error: '烘焙批次不存在' }.to_json unless roast_batch

        shipments = []
        bean_id = roast_batch.coffee_bean_id

        eligible_subs = Subscription.active_for_delivery(delivery_date)

        ActiveRecord::Base.transaction do
          eligible_subs.each do |sub|
            sub_item = sub.subscription_items.find_by(coffee_bean_id: bean_id)
            next unless sub_item

            total_weight = sub_item.quantity_grams
            next if roast_batch.coffee_bean.stock_grams < total_weight

            shipment = Shipment.create!(
              roast_batch: roast_batch,
              subscription: sub,
              address: sub.address,
              scheduled_date: delivery_date,
              status: 'pending',
              total_weight_grams: total_weight
            )

            roast_batch.coffee_bean.adjust_stock!(-total_weight)
            sub.calculate_next_delivery_date!

            shipments << shipment
          end

          pending_orders = Order.where(status: 'pending')
          pending_orders.each do |order|
            order_total_weight = 0
            has_matching_bean = false

            order.order_items.each do |item|
              next unless item.coffee_bean_id == bean_id

              has_matching_bean = true
              order_total_weight += item.quantity_grams
            end

            next unless has_matching_bean
            next if roast_batch.coffee_bean.stock_grams < order_total_weight

            shipment = Shipment.create!(
              roast_batch: roast_batch,
              order: order,
              address: order.address,
              scheduled_date: delivery_date,
              status: 'pending',
              total_weight_grams: order_total_weight
            )

            roast_batch.coffee_bean.adjust_stock!(-order_total_weight)
            order.update!(status: 'processing')

            shipments << shipment
          end
        end

        status 201
        {
          message: "成功生成 #{shipments.size} 个配送单",
          shipments: serialize(shipments, include_address: true),
          next_dates: eligible_subs.map do |s|
            { subscription_id: s.id, next_delivery_date: s.next_delivery_date }
          end
        }.to_json
      end

      post '/:id/mark_shipped' do
        shipment = Shipment.find_by(id: params[:id])
        halt 404, { error: '配送单不存在' }.to_json unless shipment

        shipment.mark_shipped!
        if shipment.order
          shipment.order.update!(status: 'shipped')
        end

        { shipment: serialize(shipment) }.to_json
      end

      post '/:id/mark_delivered' do
        shipment = Shipment.find_by(id: params[:id])
        halt 404, { error: '配送单不存在' }.to_json unless shipment

        shipment.mark_delivered!

        { shipment: serialize(shipment) }.to_json
      end

      post '/:id/cancel' do
        shipment = Shipment.find_by(id: params[:id])
        halt 404, { error: '配送单不存在' }.to_json unless shipment

        ActiveRecord::Base.transaction do
          shipment.cancel!
          bean = shipment.roast_batch.coffee_bean
          bean.adjust_stock!(shipment.total_weight_grams)

          if shipment.subscription
            shipment.subscription.update!(
              next_delivery_date: shipment.scheduled_date,
              skip_next_count: 0
            )
          end

          if shipment.order
            shipment.order.update!(status: 'pending')
          end
        end

        { shipment: serialize(shipment) }.to_json
      end
    end

    namespace '/orders' do
      get do
        scope = Order.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?

        { orders: serialize(scope, include_items: true, include_address: true) }.to_json
      end

      get '/:id' do
        order = Order.find_by(id: params[:id])
        halt 404, { error: '订单不存在' }.to_json unless order

        { order: serialize(order, include_items: true, include_address: true) }.to_json
      end
    end

    namespace '/subscriptions' do
      get do
        scope = Subscription.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(frequency: params[:frequency]) if params[:frequency].present?

        { subscriptions: serialize(scope, include_items: true, include_address: true) }.to_json
      end

      get '/upcoming' do
        date = params[:date] ? Date.parse(params[:date]) : Date.today
        subs = Subscription.active_for_delivery(date)
          .includes(:user, :address, :subscription_items)
          .order(:next_delivery_date)

        {
          delivery_date: date,
          count: subs.size,
          subscriptions: serialize(subs, include_items: true, include_address: true)
        }.to_json
      end

      get '/:id' do
        sub = Subscription.find_by(id: params[:id])
        halt 404, { error: '订阅不存在' }.to_json unless sub

        { subscription: serialize(sub, include_items: true, include_address: true) }.to_json
      end
    end

    namespace '/users' do
      get do
        users = User.order(created_at: :desc)
        { users: serialize(users) }.to_json
      end

      post '/register_admin' do
        data = parse_request_body
        halt 400, { error: '缺少必要参数' }.to_json unless data['name'] && data['email']

        user = User.new(
          name: data['name'],
          email: data['email'],
          phone: data['phone'],
          role: 'admin'
        )

        if user.save
          status 201
          { user: serialize(user) }.to_json
        else
          status 422
          { errors: user.errors.full_messages }.to_json
        end
      end
    end

    get '/dashboard' do
      today = Date.today

      {
        coffee_beans_count: CoffeeBean.count,
        active_coffee_beans_count: CoffeeBean.active.count,
        total_stock_grams: CoffeeBean.sum(:stock_grams),
        customers_count: User.where(role: 'customer').count,
        subscriptions_count: Subscription.count,
        active_subscriptions_count: Subscription.where(status: 'active').count,
        pending_orders_count: Order.where(status: 'pending').count,
        today_pending_shipments_count: Shipment.where(scheduled_date: today, status: 'pending').count,
        roast_batches_count: RoastBatch.count,
        today_roast_batches: RoastBatch.where(Date: today.all_day).count
      }.to_json
    end
  end
end
