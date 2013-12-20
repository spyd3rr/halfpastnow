class CreateAdvertisements < ActiveRecord::Migration
  def change
    create_table :advertisements do |t|
      t.integer :user_id
      t.string :adv_type
      t.string :title
      t.text :description
      t.string :name
      t.string :email
      t.integer :phone
      t.string :advertiser
      t.string :image
      t.integer :weight
      t.string :placement
      t.datetime :start
      t.datetime :end
      t.integer :views
      t.integer :clicks

      t.timestamps
    end
  end
end
