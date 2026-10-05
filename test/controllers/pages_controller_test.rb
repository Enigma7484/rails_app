require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "should get home" do
    get root_url
    assert_response :success
  end

  test "introduction is public and links to existing entry points" do
    get intro_url
    assert_response :success
    assert_select "h1", text: /Small charges/
    assert_select "a.bill-primary[href=?]", new_user_registration_path, count: 2
    assert_select "a[href=?]", new_upload_path
    assert_select "a[href=?]", new_manual_upload_path
    assert_select "button[role=tab]", count: 4
    assert_select ".bill-demo-bar", text: /Fictional CAD data/, count: 4
    assert_select ".bill-boundaries", text: /OCR.*planned.*not available today/m
  end

  test "signed in users can revisit the introduction and open their dashboard" do
    sign_in users(:one)
    get intro_url
    assert_response :success
    assert_select "a.bill-primary[href=?]", uploads_path, count: 2
    get uploads_url
    assert_response :success
    assert_select ".navbar a[href=?]", intro_path, text: "Discover"
  end

  test "public introduction does not remove authentication or overwrite a stored deep link" do
    get new_manual_upload_url
    assert_redirected_to new_user_session_path
    assert_equal new_manual_upload_path, session["user_return_to"]
    get intro_url
    assert_response :success
    assert_equal new_manual_upload_path, session["user_return_to"]
  end
end
