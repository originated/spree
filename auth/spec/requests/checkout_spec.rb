require 'spec_helper'

describe "Checkout", :js => true do
  before(:each) do
    @configuration ||= Spree::AppConfiguration.find_or_create_by_name("Default configuration")
    PAYMENT_STATES = Spree::Payment.state_machine.states.keys unless defined? PAYMENT_STATES
    SHIPMENT_STATES = Spree::Shipment.state_machine.states.keys unless defined? SHIPMENT_STATES
    ORDER_STATES = Spree::Order.state_machine.states.keys unless defined? ORDER_STATES
    Factory(:shipping_method, :zone => Spree::Zone.find_by_name('North America'))
    Factory(:payment_method, :environment => 'test')
    Factory(:product, :name => "RoR Mug")
    visit spree.root_path
  end

  it "should allow a visitor to checkout as guest, without registration" do
    click_link "RoR Mug"
    click_button "Add To Cart"
    within('h1') { page.should have_content("Shopping Cart") }
    click_link "Checkout"
    page.should have_content("Registration")

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    page.should have_content("Billing Address")
    page.should have_content("Shipping Address")

    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    page.should have_content("Your order has been processed successfully")
  end

  it "should associate an uncompleted guest order with user after log in" do
    user = Factory(:user, :email => "email@person.com", :password => "password", :password_confirmation => "password")
    click_link "RoR Mug"
    click_button "Add To Cart"
    Spree::User.count.should == 2

    visit spree.login_path
    fill_in "user_email", :with => user.email
    fill_in "user_password", :with => user.password
    click_button "Log In"

    click_link "Cart"
    page.should have_content("RoR Mug")
    within('h1') { page.should have_content("Shopping Cart") }

    click_link "Checkout"
    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    page.should have_content("Your order has been processed successfully")
    Spree::Order.count.should == 1
  end

  it "should allow a user to register during checkout" do
    pending

    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"
    page.should have_content("Registration")
    click_link "Create a new account"

    fill_in "Email", :with => "email@person.com"
    fill_in "Password", :with => "spree123"
    fill_in "Password Confirmation", :with => "spree123"
    click_button "Create"
    page.should have_content("You have signed up successfully.")

    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    page.should have_content("Your order has been processed successfully")
    Spree::Order.count.should == 1
  end

  it "the current payment method does not support profiles" do
    Factory(:authorize_net_payment_method, :environment => 'test')
    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    choose('Credit Card')
    fill_in "card_number", :with => "4111111111111111"
    fill_in "card_code", :with => "123"
    click_button "Save and Continue"
    page.should_not have_content("Confirm")
  end

  it "when no shipping methods have been configured" do
    Spree::ShippingMethod.delete_all

    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    page.should have_content("No shipping methods available")
  end

  it "user submits an invalid credit card number" do
    Factory(:bogus_payment_method, :environment => 'test')
    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    choose('Credit Card')
    fill_in "card_number", :with => "1234567890"
    fill_in "card_code", :with => "000"
    click_button "Save and Continue"
    click_button "Place Order"
    page.should have_content("Payment could not be processed")
  end

  it "completing checkout for a free order, skipping payment step" do
    Factory(:free_shipping_method, :zone => Spree::Zone.find_by_name('North America'))
    Factory(:payment_method, :environment => 'test')
    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    click_button "Save and Continue"
    click_button "Save and Continue"
    page.should have_content("Your order has been processed successfully")
  end

  it "completing checkout with an invalid address input initially" do
    Factory(:bogus_payment_method, :environment => 'test')
    click_link "RoR Mug"
    click_button "Add To Cart"
    click_link "Checkout"

    within('#guest_checkout') { fill_in "Email", :with => "spree@test.com" }
    click_button "Continue"
    page.should have_content("Shipping Address")
    page.should have_content("Billing Address")

    fill_in "First Name", :with => "Test"
    click_button "Save and Continue"
    page.should have_content("This field is required")

    str_addr = "bill_address"
    address = Factory(:address, :state => Spree::State.first)
    within('fieldset#billing') { select "United States", :from => "Country" }
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end
    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"
    page.should have_content("Shipping Method")
  end
end
