require 'spec_helper'

describe "Products" do
  before(:each) do
    visit spree.admin_path
  end

  context "listing products" do
    it "should list existing products with correct sorting" do
      Factory(:product, :name => 'apache baseball cap', :available_on => '2011-01-06 18:21:13:', :count_on_hand => '0')
      Factory(:product, :name => 'zomg shirt', :available_on => '2125-01-06 18:21:13', :count_on_hand => '5')

      click_link "Products"
      within('table.index tr:nth-child(2)') { page.should have_content("apache baseball cap") }
      within('table.index tr:nth-child(3)') { page.should have_content("zomg shirt") }

      click_link "admin_products_listing_name_title"
      within('table.index tr:nth-child(2)') { page.should have_content("zomg shirt") }
      within('table.index tr:nth-child(3)') { page.should have_content("apache baseball cap") }
    end
  end

  context "searching products" do
    it "should be able to search deleted products", :js => true do
      Factory(:product, :name => 'apache baseball cap', :available_on => '2011-01-06 18:21:13:', :deleted_at => "2011-01-06 18:21:13")
      Factory(:product, :name => 'zomg shirt', :available_on => '2125-01-06 18:21:13')

      click_link "Products"
      page.should have_content("zomg shirt")
      page.should_not have_content("apache baseball cap")
      check "Show Deleted"
      click_button "Search"
      page.should have_content("zomg shirt")
      page.should have_content("apache baseball cap")
      uncheck "Show Deleted"
      click_button "Search"
      page.should have_content("zomg shirt")
      page.should_not have_content("apache baseball cap")
    end

    it "should be able to search products by their properties" do
      Factory(:product, :name => 'apache baseball cap', :available_on => '2011-01-01 01:01:01', :sku => "A100")
      Factory(:product, :name => 'apache baseball cap2', :available_on => '2011-01-01 01:01:01', :sku => "B100")
      Factory(:product, :name => 'zomg shirt', :available_on => '2011-01-01 01:01:01', :sku => "Z100")
      Spree::Product.update_all :count_on_hand => 10

      click_link "Products"
      fill_in "search_name_contains", :with => "ap"
      click_button "Search"
      page.should have_content("apache baseball cap")
      page.should have_content("apache baseball cap2")
      page.should_not have_content("zomg shirt")

      fill_in "search_variants_including_master_sku_contains", :with => "A1"
      click_button "Search"
      page.should have_content("apache baseball cap")
      page.should_not have_content("apache baseball cap2")
      page.should_not have_content("zomg shirt")
    end
  end

  context "creating a new product" do
    before(:each) do
      click_link "Products"
      click_link "admin_new_product"
      within('#new_product') { page.should have_content("SKU") }
    end

    it "should allow an admin to create a new product", :js => true do
      fill_in "product_name", :with => "Baseball Cap"
      fill_in "product_sku", :with => "B100"
      fill_in "product_price", :with => "100"
      fill_in "product_available_on", :with => "2011/01/24"
      click_button "Create"
      page.should have_content("successfully created!")
      fill_in "product_on_hand", :with => "100"
      click_button "Update"
      page.should have_content("successfully updated!")
    end

    it "should show validation errors", :js => true do
      click_button "Create"
      page.should have_content("Name can't be blank")
      page.should have_content("Price can't be blank")
    end
  end

  context "cloning a product" do
    it "should allow an admin to clone a product" do
      Factory(:product, :name => 'apache baseball cap', :available_on => '2011-01-01 01:01:01', :sku => "A100")

      click_link "Products"
      within('table#listing_products tr:nth-child(2)') { click_link "Clone" }
      page.should have_content("Product has been cloned")
    end
  end

  context "uploading a product image" do
    it "should allow an admin to upload an image and edit it for a product" do
      Factory(:product, :name => 'apache baseball cap', :available_on => '2011-01-01 01:01:01', :sku => "A100")
      Factory(:product, :name => 'apache baseball cap2', :available_on => '2011-01-01 01:01:01', :sku => "B100")
      Factory(:product, :name => 'zomg shirt', :available_on => '2011-01-01 01:01:01', :sku => "Z100")
      Spree::Product.update_all :count_on_hand => 10

      click_link "Products"
      within('table#listing_products tr:nth-child(2)') { click_link "Edit" }
      click_link "Images"
      click_link "new_image_link"
      absolute_path = File.expand_path(Rails.root.join('..', '..', 'features', 'step_definitions', 'ror_ringer.jpeg'))
      attach_file('image_attachment', absolute_path)
      click_button "Update"
      page.should have_content("successfully created!")
      within('table.index tr:nth-child(2)') { click_link "Edit" }
      fill_in "image_alt", :with => "ruby on rails t-shirt"
      click_button "Update"
      page.should have_content("successfully updated!")
      page.should have_content("ruby on rails t-shirt")
    end
  end
end
