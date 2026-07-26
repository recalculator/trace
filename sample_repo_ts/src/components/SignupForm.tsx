import { signup } from "../api/routes";

interface SignupFormProps {
  onDone: (email: string) => void;
}

export function SignupForm(props: SignupFormProps) {
  const submit = (email: string, password: string) => {
    const result = signup({ email, password, displayName: "" });
    props.onDone(email);
    return result;
  };

  return <form onSubmit={() => submit("a@b.co", "password123")}>Sign up</form>;
}
