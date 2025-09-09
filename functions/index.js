const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

admin.initializeApp();

const SENDGRID_API_KEY = process.env.SENDGRID_KEY ||
  require("firebase-functions").config().sendgrid.key;

sgMail.setApiKey(SENDGRID_API_KEY);

setGlobalOptions({maxInstances: 10});

exports.sendDriverStatusEmail = onDocumentWritten(
    "drivers/{driverId}",
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (!before || !after || before.status === after.status) return null;

      const {email, name} = after;
      const time = new Date().toLocaleString();

      try {
        if (after.status === "approved") {
          const msg = {
            to: email,
            from: "johnyly168@gmail.com",
            subject: "Your VanGo Application Has Been Approved!",
            html: `
            <p>Hi <strong>${name}</strong>,</p>
            <p>Congratulations! Your application to join 
            <strong>VanGo</strong> has been <strong>approved</strong>.</p>
            <p>You can now log in and start using your account.</p>
            <p>Approved on ${time}</p>
            <p>Welcome aboard, and thank you for joining 
            <strong>VanGo</strong>!</p>
          `,
          };
          await sgMail.send(msg);
          console.log("✅ Approval email sent to", email);
        } else if (after.status === "rejected") {
          const reason = after.reason || "No reason provided";
          const msg = {
            to: email,
            from: "johnyly168@gmail.com",
            subject: "Your VanGo Application Has Been Rejected",
            html: `
            <p>Hi <strong>${name}</strong>,</p>
            <p>We regret to inform you that your application to 
            join <strong>VanGo</strong> has been <strong>rejected</strong>.</p>
            <p>Reason: ${reason}</p>
            <p>Rejected on ${time}</p>
            <p>If you have any questions, contact us at 
            <a href="mailto:support@vango.com">support@vango.com</a></p>
          `,
          };
          await sgMail.send(msg);
          console.log("✅ Rejection email sent to", email);
        }
      } catch (error) {
        console.error(
            "❌ Error sending email via SendGrid:",
        error.response ? error.response.body : error,
        );
      }

      return null;
    },
);
