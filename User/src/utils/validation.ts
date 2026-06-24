import validator from "validator";

export const validateSignupData = (req: any) => {
  const { firstName, lastName, email, password } = req.body;

  if (!firstName || !lastName) {
    throw new Error("Name is not valid");
  } else if (!validator.isEmail(email)) {
    throw new Error("Name is not valid");
  } else if (!validator.isStrongPassword(password)) {
    throw new Error("password is not strong");
  }
};

export const validateEditProfileData = (body: any) => {
  const allowedUpdates = [
    "firstName",
    "lastName",
    "photoUrl",
    "skills",
    "about",
    "photoUrl",
  ];

  let isAllowedUpdate = false;
  Object.keys(body).forEach((a) => {
    if (allowedUpdates.includes(a)) {
      isAllowedUpdate = true;
    }
  });
  return isAllowedUpdate;
};
