class AddPasswordResetVerifications < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :otp_verifications, name: "chk_otp_verifications_purpose"
    remove_check_constraint :otp_verifications, name: "chk_otp_verifications_status"
    add_check_constraint :otp_verifications, "purpose between 0 and 3",
      name: "chk_otp_verifications_purpose"
    add_check_constraint :otp_verifications, "status between 0 and 4",
      name: "chk_otp_verifications_status"
  end

  def down
    execute "UPDATE otp_verifications SET status = 3 WHERE status = 4"
    execute "DELETE FROM otp_verifications WHERE purpose = 3"
    remove_check_constraint :otp_verifications, name: "chk_otp_verifications_purpose"
    remove_check_constraint :otp_verifications, name: "chk_otp_verifications_status"
    add_check_constraint :otp_verifications, "purpose between 0 and 2",
      name: "chk_otp_verifications_purpose"
    add_check_constraint :otp_verifications, "status between 0 and 3",
      name: "chk_otp_verifications_status"
  end
end
