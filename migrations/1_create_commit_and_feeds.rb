Sequel.migration do
  change do
    create_table(:commits) do
      Integer :feed_id, index: true, null: false
      String :sha, size: 40, index: true, unique: true, null: false
      String :author_email, null: false
      String :author_name, null: false
      column :message, :text, null: false
      Time :date, null: false
    end
    create_table(:feeds) do
      primary_key :id
      String :name, null: false, index: true
      column :content, :text
      Time :updated_at
    end
  end
end
