require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/json'
require 'sinatra/namespace'
require 'rack/cors'
require 'json'

set :database_file, './database.yml'
set :environments, %w[development test production]

Dir[File.join(File.dirname(__FILE__), 'app', 'models', '*.rb')].each { |f| require f }
Dir[File.join(File.dirname(__FILE__), 'app', 'services', '**', '*.rb')].each { |f| require f }

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get post put patch delete options]
  end
end

class CoffeeRoasteryAPI < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  register Sinatra::Namespace
  helpers Sinatra::JSON

  before do
    content_type :json
  end

  helpers do
    def current_user
      user_id = request.env['HTTP_X_USER_ID'] || params[:user_id]
      @current_user ||= User.find_by(id: user_id) if user_id
    end

    def authenticate!
      unless current_user
        halt 401, { error: '未授权，请先登录' }.to_json
      end
    end

    def require_admin!
      authenticate!
      unless current_user.admin?
        halt 403, { error: '无权限执行此操作' }.to_json
      end
    end

    def parse_request_body
      body = request.body.read
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      halt 400, { error: '请求体格式错误' }.to_json
    end

    def validate_promo_code(code)
      promo, error = PromotionCode.lookup_and_validate(code)
      halt 422, { error: error }.to_json if error
      promo
    end

    def promotion_code_attributes(promo)
      {
        id: promo.id,
        code: promo.code,
        discount_type: promo.discount_type,
        discount_type_display: promo.discount_type_display,
        discount_value: promo.discount_value.to_f,
        discount_description: promo.discount_description,
        description: promo.description
      }
    end

    def serialize(object, options = {})
      return nil if object.nil?

      if object.respond_to?(:to_ary)
        object.map { |item| serialize_single(item, options) }
      else
        serialize_single(object, options)
      end
    end

    def serialize_single(object, options = {})
      case object
      when User
        user_attributes(object)
      when Address
        address_attributes(object)
      when CoffeeBean
        coffee_bean_attributes(object)
      when Order
        order_attributes(object, options)
      when OrderItem
        order_item_attributes(object)
      when Subscription
        subscription_attributes(object, options)
      when SubscriptionItem
        subscription_item_attributes(object)
      when RoastBatch
        roast_batch_attributes(object, options)
      when Shipment
        shipment_attributes(object, options)
      when PromotionCode
        promotion_code_attributes(object)
      else
        object.as_json
      end
    end

    def user_attributes(user)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        created_at: user.created_at
      }
    end

    def address_attributes(address)
      {
        id: address.id,
        user_id: address.user_id,
        recipient_name: address.recipient_name,
        phone: address.phone,
        province: address.province,
        city: address.city,
        district: address.district,
        detail: address.detail,
        full_address: address.full_address,
        is_default: address.is_default,
        locked: address.locked
      }
    end

    def coffee_bean_attributes(bean)
      {
        id: bean.id,
        name: bean.name,
        origin: bean.origin,
        roast_level: bean.roast_level,
        roast_level_display: bean.roast_level_display,
        flavor_description: bean.flavor_description,
        stock_grams: bean.stock_grams,
        price_per_100g: bean.price_per_100g.to_f,
        active: bean.active
      }
    end

    def order_attributes(order, options = {})
      result = {
        id: order.id,
        user_id: order.user_id,
        address_id: order.address_id,
        status: order.status,
        status_display: order.status_display,
        order_type: order.order_type,
        subtotal: order.subtotal.to_f,
        discount_amount: order.discount_amount.to_f,
        total_amount: order.total_amount.to_f,
        delivered_at: order.delivered_at,
        created_at: order.created_at
      }
      if options[:include_items]
        result[:order_items] = order.order_items.map { |item| order_item_attributes(item) }
      end
      if options[:include_address] && order.address
        result[:address] = address_attributes(order.address)
      end
      if options[:include_promo] && order.promotion_code
        result[:promotion_code] = promotion_code_attributes(order.promotion_code)
      end
      result
    end

    def order_item_attributes(item)
      {
        id: item.id,
        order_id: item.order_id,
        coffee_bean_id: item.coffee_bean_id,
        coffee_bean_name: item.coffee_bean.name,
        quantity_grams: item.quantity_grams,
        unit_price: item.unit_price.to_f,
        subtotal: item.subtotal.to_f
      }
    end

    def subscription_attributes(sub, options = {})
      result = {
        id: sub.id,
        user_id: sub.user_id,
        address_id: sub.address_id,
        frequency: sub.frequency,
        frequency_display: sub.frequency_display,
        status: sub.status,
        status_display: sub.status_display,
        start_date: sub.start_date,
        next_delivery_date: sub.next_delivery_date,
        skip_next_count: sub.skip_next_count,
        subtotal: sub.subtotal.to_f,
        discount_amount: sub.discount_amount.to_f,
        total_amount_per_delivery: sub.total_amount_per_delivery.to_f,
        created_at: sub.created_at
      }
      if options[:include_items]
        result[:subscription_items] = sub.subscription_items.map { |item| subscription_item_attributes(item) }
      end
      if options[:include_address] && sub.address
        result[:address] = address_attributes(sub.address)
      end
      if options[:include_promo] && sub.promotion_code
        result[:promotion_code] = promotion_code_attributes(sub.promotion_code)
      end
      result
    end

    def subscription_item_attributes(item)
      {
        id: item.id,
        subscription_id: item.subscription_id,
        coffee_bean_id: item.coffee_bean_id,
        coffee_bean_name: item.coffee_bean.name,
        quantity_grams: item.quantity_grams,
        unit_price: item.unit_price.to_f,
        subtotal: item.subtotal.to_f
      }
    end

    def roast_batch_attributes(batch, options = {})
      result = {
        id: batch.id,
        batch_number: batch.batch_number,
        coffee_bean_id: batch.coffee_bean_id,
        coffee_bean_name: batch.coffee_bean.name,
        roast_quantity_grams: batch.roast_quantity_grams,
        roasted_at: batch.roasted_at,
        notes: batch.notes,
        created_at: batch.created_at
      }
      if options[:include_shipments]
        result[:shipments] = batch.shipments.map { |s| shipment_attributes(s) }
      end
      result
    end

    def shipment_attributes(shipment, options = {})
      result = {
        id: shipment.id,
        roast_batch_id: shipment.roast_batch_id,
        subscription_id: shipment.subscription_id,
        order_id: shipment.order_id,
        address_id: shipment.address_id,
        status: shipment.status,
        status_display: shipment.status_display,
        scheduled_date: shipment.scheduled_date,
        shipped_at: shipment.shipped_at,
        delivered_at: shipment.delivered_at,
        total_weight_grams: shipment.total_weight_grams,
        recipient_name: shipment.recipient_name,
        shipping_address: shipment.shipping_address,
        created_at: shipment.created_at
      }
      if options[:include_address]
        result[:address] = address_attributes(shipment.address)
      end
      result
    end
  end

  get '/' do
    {
      service: '社区咖啡烘焙工坊订阅服务 API',
      version: '1.0.0',
      endpoints: {
        customers: '/api/customers/*',
        admin: '/api/admin/*',
        public: '/api/coffee_beans'
      }
    }.to_json
  end

  get '/api/health' do
    { status: 'ok', database: ActiveRecord::Base.connection.active? }.to_json
  end
end

Dir[File.join(File.dirname(__FILE__), 'app', 'routes', '*.rb')].each { |f| require f }
