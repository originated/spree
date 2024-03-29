require 'spec_helper'

describe Spree::Order do
  before(:each) do
    @configuration ||= Spree::AppConfiguration.find_or_create_by_name("Default configuration")
  end

  context 'validation' do
    it { should have_valid_factory(:order) }
  end

  let(:order) { Factory(:order) }
  let(:gateway) { Spree::Gateway::Bogus.new(:name => "Credit Card", :active => true) }

  before do
    Spree::Gateway.stub :current => gateway
    Spree::User.stub(:current => mock_model(Spree::User, :id => 123))
  end

  context "factory" do
    it "should change the Orders count by 1 after factory has been executed" do
      lambda do
        Factory(:order_with_totals)
      end.should change(Spree::Order, :count).by(1)
    end
    context 'line_item' do
      let(:order) { Factory(:order_with_totals) }
      it "should have a line_item attached to it" do
        order.line_items.size.should == 1
      end
      it "should be attached to last line_item created " do
        order.line_items.first.id.should == Spree::LineItem.last.id
      end
    end
  end

  context "#products" do
    it "should return ordered products" do
      variant1 = mock_model(Spree::Variant, :product => "product1")
      variant2 = mock_model(Spree::Variant, :product => "product2")
      line_items = [mock_model(Spree::LineItem, :variant => variant1), mock_model(Spree::LineItem, :variant => variant2)]
      order.stub(:line_items => line_items)
      order.products.should == ['product1', 'product2']
    end
  end

  context "#save" do
    it "should create guest user (when no user assigned)" do
      order.save
      order.user.should_not be_nil
    end

    context "when associated with a registered user" do
      let(:order) { Spree::Order.new }
      let(:user) { Factory(:user, :email => "user@registered.com") }
      before {
        order.user = user
      }
      it "should not remove the user" do
        order.save
        order.user.should == user
      end

      it "should assign the email address of the user" do
        order.save
        order.email.should == user.email
      end

      it "should accept the sample admin email address" do
        user.stub :email => "spree@example.com"
        order.save
        order.email.should == user.email
      end

      it "should reject the automatic email for anonymous users" do
        user.stub :anonymous? => true
        order.save
        order.email.should be_blank
      end

    end

    it "should destroy any line_items with zero quantity"
  end

  context "#next!" do
    context "when current state is confirm" do
      before { order.state = "confirm" }
      it "should finalize order when transitioning to complete state" do
        order.should_receive(:finalize!)
        order.next!
      end

       context "when credit card payment fails" do
         before do
           order.stub(:process_payments!).and_raise(Spree::Core::GatewayError)
         end

         context "when not configured to allow failed payments" do
            before do
              Spree::Config.set :allow_checkout_on_gateway_error => false
            end

            it "should not complete the order" do
               order.next
               order.state.should == "confirm"
             end
          end

         context "when configured to allow failed payments" do
           before do
             Spree::Config.set :allow_checkout_on_gateway_error => true
           end

           it "should complete the order" do
             pending
              order.next
              order.state.should == "complete"
            end

         end

       end
    end
    context "when current state is address" do
      let(:sales_tax) { mock_model Spree::Calculator::SalesTax, :description => "Sales Tax" }
      let(:rate) { mock_model Spree::TaxRate, :amount => 10, :calculator => sales_tax }
      let(:rate_1) { mock_model Spree::TaxRate, :amount => 15, :calculator => sales_tax }

      before do
        order.state = "address"
        Spree::TaxRate.stub :match => [rate, rate_1]
      end

      it "should create a tax charge when transitioning to delivery state" do
        [rate, rate_1].each { |r| r.should_receive(:create_adjustment) }
        order.next!
      end

      context "when a tax charge already exists" do
        let(:old_charge) { mock_model Spree::Adjustment }
        before { order.stub_chain :adjustments, :tax => [old_charge] }

        it "should remove an existing tax charge (for the old rate)" do
          [rate, rate_1].each { |r| r.should_receive(:create_adjustment) }
          old_charge.should_receive :destroy
          order.next
        end

        it "should remove an existing tax charge if there is no longer a relevant tax rate" do
          Spree::TaxRate.stub :match => []
          old_charge.stub :originator => mock_model(Spree::TaxRate)
          old_charge.should_receive :destroy
          order.next
        end
      end

    end

    context "when current state is delivery" do
      before do
        order.state = "delivery"
        order.shipping_method = mock_model(Spree::ShippingMethod).as_null_object
        order.stub :total => 10.0
      end

      context "when transitioning to payment state" do
        it "should create a shipment" do
          order.next!
          order.state.should == 'payment'
          order.shipments.size.should == 1
        end
      end
    end

  end

  context "#generate_order_number" do
    it "should generate a random string" do
      order.generate_order_number.is_a?(String).should be_true
      (order.generate_order_number.to_s.length > 0).should be_true
    end
  end

  context "#create" do
    it "should assign an order number" do
      order = Spree::Order.create
      order.number.should_not be_nil
    end
  end

  context "#finalize!" do
    let(:order) { Spree::Order.create }
    it "should set completed_at" do
      order.should_receive :completed_at=
      order.finalize!
    end
    it "should sell inventory units" do
      Spree::InventoryUnit.should_receive(:assign_opening_inventory).with(order)
      order.finalize!
    end
    it "should change the shipment state to ready if order is paid"

    after { Spree::Config.set :track_inventory_levels => true }
    it "should not sell inventory units if track_inventory_levels is false" do
      Spree::Config.set :track_inventory_levels => false
      Spree::InventoryUnit.should_not_receive(:sell_units)
      order.finalize!
    end

    it "should send an order confirmation email" do
      mail_message = mock "Mail::Message"
      Spree::OrderMailer.should_receive(:confirm_email).with(order).and_return mail_message
      mail_message.should_receive :deliver
      order.finalize!
    end

    it "should freeze optional adjustments" do
      Spree::OrderMailer.stub_chain :confirm_email, :deliver
      adjustment = mock_model(Spree::Adjustment)
      order.stub_chain :adjustments, :optional => [adjustment]
      adjustment.should_receive(:update_attribute).with("locked", true)
      order.finalize!
    end

    it "should log state event" do
      order.state_events.should_receive(:create)
      order.finalize!
    end
  end

  context "#process_payments!" do
    it "should process the payments" do
      order.stub!(:payments).and_return([mock(Spree::Payment)])
      order.payment.should_receive(:process!)
      order.process_payments!
    end
  end

  context "#outstanding_balance" do
    it "should return positive amount when payment_total is less than total" do
      order.payment_total = 20.20
      order.total = 30.30
      order.outstanding_balance.should == 10.10
    end
    it "should return negative amount when payment_total is greater than total" do
      order.total = 8.20
      order.payment_total = 10.20
      order.outstanding_balance.should be_within(0.001).of(-2.00)
    end

  end

  context "#outstanding_balance?" do
    it "should be true when total greater than payment_total" do
      order.total = 10.10
      order.payment_total = 9.50
      order.outstanding_balance?.should be_true
    end
    it "should be true when total less than payment_total" do
      order.total = 8.25
      order.payment_total = 10.44
      order.outstanding_balance?.should be_true
    end
    it "should be false when total equals payment_total" do
      order.total = 10.10
      order.payment_total = 10.10
      order.outstanding_balance?.should be_false
    end
  end

  context "#outstanding_credit" do
  end

  context "#complete?" do
    it "should indicate if order is complete" do
      order.completed_at = nil
      order.complete?.should be_false

      order.completed_at = Time.now
      order.completed?.should be_true
    end
  end

  context "#backordered?" do
    it "should indicate whether any units in the order are backordered" do
      order.stub_chain(:inventory_units, :backorder).and_return []
      order.backordered?.should be_false
      order.stub_chain(:inventory_units, :backorder).and_return [mock_model(Spree::InventoryUnit)]
      order.backordered?.should be_true
    end

    it "should always be false when inventory tracking is disabled" do
      pending
      Spree::Config.set :track_inventory_levels => false
      order.stub_chain(:inventory_units, :backorder).and_return [mock_model(Spree::InventoryUnit)]
      order.backordered?.should be_false
    end
  end

  context "#update!" do
    # before { Order.should_receive :update_all }

    context "when payments are sufficient" do
      it "should set payment_state to paid" do
        order.stub(:total => 100.01, :payment_total => 100.012343)
        order.update!
        order.payment_state.should == "paid"
      end
    end

    context "when payments are insufficient" do
      let(:payments) { mock "payments", :completed => [], :first => mock_model(Spree::Payment, :checkout? => false) }
      before { order.stub :total => 100, :payment_total => 50, :payments => payments }

      context "when last payment did not fail" do
        before { payments.stub :last => mock("payment", :state => 'pending') }
        it "should set payment_state to balance_due" do
          order.update!
          order.payment_state.should == "balance_due"
        end
      end

      context "when last payment failed" do
        before { payments.stub :last => mock("payment", :state => 'failed') }
        it "should set the payment_state to failed" do
          order.update!
          order.payment_state.should == "failed"
        end
      end
    end

    context "when payments are more than sufficient" do
      it "should set the payment_state to credit_owed" do
        order.stub(:total => 100, :payment_total => 150)
        order.update!
        order.payment_state.should == "credit_owed"
      end
    end

    context "when there are shipments" do
      let(:shipments) { [mock_model(Spree::Shipment, :update! => nil), mock_model(Spree::Shipment, :update! => nil)] }
      before do
        shipments.stub :shipped => []
        shipments.stub :ready => []
        shipments.stub :pending => []
        order.stub :shipments => shipments
      end

      it "should set the correct shipment_state (when all shipments are shipped)" do
        shipments.stub :shipped => [mock_model(Spree::Shipment), mock_model(Spree::Shipment)]
        order.update!
        order.shipment_state.should == "shipped"
      end

      it "should set the correct shipment_state (when some units are backordered)" do
        shipments.stub :shipped => [mock_model(Spree::Shipment)]
        order.stub(:backordered?).and_return true
        order.update!
        order.shipment_state.should == "backorder"
      end

      it "should set the shipment_state to partial (when some of the shipments have shipped)" do
        shipments.stub :shipped => [mock_model(Spree::Shipment)]
        shipments.stub :ready => [mock_model(Spree::Shipment)]
        order.update!
        order.shipment_state.should == "partial"
      end

      it "should set the correct shipment_state (when some of the shipments are ready)" do
        shipments.stub :ready => [mock_model(Spree::Shipment), mock_model(Spree::Shipment)]
        order.update!
        order.shipment_state.should == "ready"
      end

      it "should set the shipment_state to pending (when all shipments are pending)" do
        shipments.stub :pending => [mock_model(Spree::Shipment), mock_model(Spree::Shipment)]
        order.update!
        order.shipment_state.should == "pending"
      end
    end

    context "when there are update hooks" do
      before { Spree::Order.register_update_hook :foo }
      after { Spree::Order.update_hooks.clear }
      it "should call each of the update hooks" do
        order.should_receive :foo
        order.update!
      end
    end

    context "when there is a single checkout payment" do
      before { order.stub(:payment => mock_model(Spree::Payment, :checkout? => true, :amount => 11), :total => 22) }

      it "should update the payment amount to order total" do
        order.payment.should_receive(:update_attributes_without_callbacks).with(:amount => order.total)
        order.update!
      end
    end

    it "should set the correct shipment_state (when there are no shipments)" do
      order.update!
      order.shipment_state.should == nil
    end

    it "should call update_totals" do
      order.should_receive(:update_totals).twice
      order.update!
    end

    it "should call adjustment#update on every adjustment}" do
      # adjustment = mock_model(Adjustment, :amount => 5, :applicable? => true, :update! => true)
      adjustment = Factory(:adjustment, :order => order, :amount => 5)
      # TODO: Restore this example. Stubbing adjustments doesn't work, need a proper collection
      # so we can use adjustments.eligible
      # order.stub(:adjustments => [adjustment])
      # order.adjustments.stub(:reload).and_return([adjustment])
      # adjustment.should_receive(:update!)
      # order.update!
    end

    it "should call update! on every shipment" do
      # shipment = mock_model Shipment
      shipment = Factory(:shipment)
      order.shipments = [shipment]
      shipment.should_receive(:update!)
      order.update!
    end
  end

  context "#update_totals" do
    it "should set item_total to the sum of line_item amounts" do
      line_items = [ mock_model(Spree::LineItem, :amount => 100), mock_model(Spree::LineItem, :amount => 50) ]
      order.stub(:line_items => line_items)
      order.update!
      order.item_total.should == 150
    end
    it "should set payments_total to the sum of completed payment amounts" do
      payments = [ mock_model(Spree::Payment, :amount => 100, :checkout? => false), mock_model(Spree::Payment, :amount => -10, :checkout? => false) ]
      payments.stub(:completed => payments)
      order.stub(:payments => payments)
      order.update!
      order.payment_total.should == 90
    end

    context "with adjustments" do
      before do
        Factory(:adjustment, :order => order, :amount => 10)
        Factory(:adjustment, :order => order, :amount => 5)
        a = Factory(:adjustment, :order => order, :amount => -2, :eligible => false)
        a.update_attribute_without_callbacks(:eligible, false)
        order.stub(:update_adjustments, nil) # So the last adjustment remains ineligible
        order.adjustments.reload
      end
      it "should set adjustment_total to the sum of the eligible adjustment amounts" do
        order.update!
        order.adjustment_total.to_i.should == 15
      end
      it "should set the total to the sum of item and adjustment totals" do
        line_items = [ mock_model(Spree::LineItem, :amount => 100), mock_model(Spree::LineItem, :amount => 50) ]
        order.stub(:line_items => line_items)
        order.update!
        order.total.to_i.should == 165
      end
    end

  end

  context "#payment_method" do
    it "should return payment.payment_method if payment is present" do
      payments = [Factory(:payment)]
      payments.stub(:completed => payments)
      order.stub(:payments => payments)
      order.payment_method.should == order.payments.first.payment_method
    end

    it "should return the first payment method from available_payment_methods if payment is not present" do
      Factory(:payment_method, :environment => 'test')
      order.payment_method.should == order.available_payment_methods.first
    end
  end

  context "#allow_checkout?" do
    it "should be true if there are line_items in the order" do
      order.stub_chain(:line_items, :count => 1)
      order.checkout_allowed?.should be_true
    end
    it "should be false if there are no line_items in the order" do
      order.stub_chain(:line_items, :count => 0)
      order.checkout_allowed?.should be_false
    end
  end

  context "item_count" do
    it "should return the correct number of items" do
      line_items = [ mock_model(Spree::LineItem, :quantity => 2), mock_model(Spree::LineItem, :quantity => 1) ]
      order.stub :line_items => line_items
      order.item_count.should == 3
    end
  end

  context "in the cart state" do
    it "should not validate email address" do
      order.state = "cart"
      order.email = nil
      order.should be_valid
    end
  end

  context "#can_cancel?" do

    %w(pending backorder ready).each do |shipment_state|
      it "should be true if shipment_state is #{shipment_state}" do
        order.stub :completed? => true
        order.shipment_state = shipment_state
        order.can_cancel?.should be_true
      end
    end

    (SHIPMENT_STATES - %w(pending backorder ready)).each do |shipment_state|
      it "should be false if shipment_state is #{shipment_state}" do
        order.stub :completed? => true
        order.shipment_state = shipment_state
        order.can_cancel?.should be_false
      end
    end

  end

  context "#cancel" do
    before do
      order.stub :completed? => true
      order.stub :allow_cancel? => true
    end
    it "should send a cancel email" do
      mail_message = mock "Mail::Message"
      Spree::OrderMailer.should_receive(:cancel_email).with(order).and_return mail_message
      mail_message.should_receive :deliver
      order.cancel!
    end
    it "should restock inventory"
    it "should change shipment status (unless shipped)"
  end

  context "with adjustments" do
    let(:adjustment1) { mock_model(Spree::Adjustment, :amount => 5) }
    let(:adjustment2) { mock_model(Spree::Adjustment, :amount => 10) }

    context "#ship_total" do
      it "should return the correct amount" do
        order.stub_chain :adjustments, :shipping => [adjustment1, adjustment2]
        order.ship_total.should == 15
      end
    end

    context "#tax_total" do
      it "should return the correct amount" do
        order.stub_chain :adjustments, :tax => [adjustment1, adjustment2]
        order.tax_total.should == 15
      end
    end
  end

  context "#can_cancel?" do
    it "should be false for completed order in the canceled state" do
      order.state = 'canceled'
      order.shipment_state = 'ready'
      order.completed_at = Time.now
      order.can_cancel?.should be_false
    end
  end

  context "rate_hash" do
    let(:shipping_method_1) { mock_model Spree::ShippingMethod, :name => 'Air Shipping', :id => 1, :calculator => mock('calculator') }
    let(:shipping_method_2) { mock_model Spree::ShippingMethod, :name => 'Ground Shipping', :id => 2, :calculator => mock('calculator') }

    before do
      shipping_method_1.calculator.stub(:compute).and_return(10.0)
      shipping_method_2.calculator.stub(:compute).and_return(0.0)
      order.stub(:available_shipping_methods => [ shipping_method_1, shipping_method_2 ])
    end

    it "should return shipping methods sorted by cost" do
      order.rate_hash.should == [{:shipping_method => shipping_method_2, :cost => 0.0, :name => "Ground Shipping", :id => 2},
                                  {:shipping_method => shipping_method_1, :cost => 10.0, :name => "Air Shipping", :id => 1}]
    end

    it "should not return shipping methods with nil cost" do
      shipping_method_1.calculator.stub(:compute).and_return(nil)
      order.rate_hash.should == [{:shipping_method => shipping_method_2, :cost => 0.0, :name => "Ground Shipping", :id => 2}]
    end

  end

  context "insufficient_stock_lines" do
    let(:line_item) { mock_model Spree::LineItem, :insufficient_stock? => true }

    before { order.stub(:line_items => [line_item]) }

    it "should return line_item that has insufficent stock on hand" do
      order.insufficient_stock_lines.size.should == 1
      order.insufficient_stock_lines.include?(line_item).should be_true
    end

  end

  context "create_tax_charge!" do
    let(:sales_tax) { mock_model Spree::Calculator::SalesTax, :compute => 3, :[]= => nil, :description => "Money for the man" }
    let(:rate) { Spree::TaxRate.create(:amount => 0.05) }
    let(:rate_1) { Spree::TaxRate.create(:amount => 0.15) }

    it "should destory all existing tax adjustments" do
      adjustment = mock_model(Spree::Adjustment, :amount => 5, :calculator => :sales_tax)
      adjustment.should_receive :destroy

      order.stub_chain :adjustments, :tax => [adjustment]
      order.create_tax_charge!
    end

    it "should create adjustments with correct labels for matched rates" do
      [rate, rate_1].each {|r| r.stub :calculator => sales_tax }
      Spree::TaxRate.stub :match => [rate, rate_1]

      order.create_tax_charge!
      order.adjustments.tax.size.should == 2

      ["Money for the man 5.0%", "Money for the man 15.0%"].each do |label|
        order.adjustments.tax.map(&:label).include?(label).should be_true
      end
    end

    context "when :show_price_inc_vat is true" do
      before { Spree::Config.set :show_price_inc_vat => true }

      it "should use default countries rate when none match address" do
        pending
        Spree::TaxRate.stub :match => []
        rate.stub_chain :zone, :country_list => [mock_model(Spree::Country, :id => Spree::Config[:default_country_id])]
        rate_1.stub_chain :zone, :country_list => []
        Spree::TaxRate.stub :all => [rate, rate_1]

        rate.should_receive(:create_adjustment).at_least(:once)
        rate_1.should_not_receive(:create_adjustment)
        order.create_tax_charge!
      end
    end
  end
end
