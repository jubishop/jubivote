Sequel.migration {
  change {
    create_table(:responders) {
      primary_key :id
      foreign_key :poll_id, :polls, on_delete: :cascade, on_update: :cascade
      String :email, null: false, index: true
      unique %i[poll_id email]
    }
  }
}
