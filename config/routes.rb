ActionController::Routing::Routes.draw do |map|
  map.resources :interfaces, :member => { :instant_rate => :get }, :collection => { :scan => :get }

  map.resources :configurations, :collection => {:doreload => :get}

  map.resources :users

  map.resources :avoid_balancing_hosts

  map.resources :avoid_proxy_hosts

  map.resources :iproutes

  map.resources :audits, :member => { :go_back => :get }

  map.resources :provider_groups, :member => { :instant_rate => :get }

  map.resources :providers

  map.resources :contracts, :member => { :instant => :get},
                :collection => { :free_ips => :get, :ips => :get, :arping_mac_address =>
                :get, :excel => :get }

  map.resources :clients, :has_many => :contracts, :collection => { :names => :get }

  map.resources :plans

  map.resources :graphs

  map.resource :user_session

  map.resource :about

  map.resource :dashboard, :collection => { :cpu => :get , :services => :get, :load_average => :get, :reboot => :get, :halt => :get }

  map.backup '/backup', :controller => 'backup', :action => 'index'
  map.login '/login', :controller => 'user_sessions', :action => 'new'
  map.logout '/logout', :controller => 'user_sessions', :action => 'destroy'

  map.root :controller => "user_sessions", :action => "new"

  # The priority is based upon order of creation: first created -> highest priority.

  # Sample of regular route:
  #   map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   map.purchase 'products/:id/purchase', :controller => 'catalog', :action => 'purchase'
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   map.resources :products

  # Sample resource route with options:
  #   map.resources :products, :member => { :short => :get, :toggle => :post }, :collection => { :sold => :get }

  # Sample resource route with sub-resources:
  #   map.resources :products, :has_many => [ :comments, :sales ], :has_one => :seller

  # Sample resource route with more complex sub-resources
  #   map.resources :products do |products|
  #     products.resources :comments
  #     products.resources :sales, :collection => { :recent => :get }
  #   end

  # Sample resource route within a namespace:
  #   map.namespace :admin do |admin|
  #     # Directs /admin/products/* to Admin::ProductsController (app/controllers/admin/products_controller.rb)
  #     admin.resources :products
  #   end

  # You can have the root of your site routed with map.root -- just remember to delete public/index.html.
  # map.root :controller => "welcome"

  # See how all your routes lay out with "rake routes"

  # Install the default routes as the lowest priority.
  # Note: These default routes make all actions in every controller accessible via GET requests. You should
  # consider removing or commenting them out if you're using named routes and resources.
  #map.connect ':controller/:action/:id'

  map.connect ':controller/:action'
end
