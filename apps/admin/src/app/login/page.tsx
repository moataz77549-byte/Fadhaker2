"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { BrandMark } from "@/components/BrandMark";
import { supabase } from "@/lib/supabase";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    if (!supabase) {
      setErrorMessage("إعدادات Supabase غير مكتملة في بيئة الإدارة.");
      return;
    }
    setIsLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setIsLoading(false);
    if (error) {
      setErrorMessage("تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور أو صلاحية الحساب.");
      return;
    }
    router.replace("/dashboard");
  };

  return (
    <div style={{
      minHeight: "100vh",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      backgroundColor: "#0E1726",
      padding: "1.5rem"
    }}>
      <div style={{
        maxWidth: "420px",
        width: "100%",
        backgroundColor: "#172235",
        borderRadius: "16px",
        padding: "2.5rem 2rem",
        border: "1px solid #243B6B",
        boxShadow: "0 12px 30px rgba(0,0,0,0.4)"
      }}>
        <div style={{ textAlign: "center", marginBottom: "2rem" }}>
          <div style={{ display: "inline-block", marginBottom: "1rem" }}>
            <BrandMark size={64} />
          </div>
          <h1 style={{ color: "#F8F6F1", fontSize: "1.6rem", fontWeight: 700 }}>
            تسجيل الدخول الإداري
          </h1>
          <p style={{ color: "#9DAEC6", fontSize: "0.9rem", marginTop: "0.3rem" }}>
            بوابة الإدارة المركزية لمنصة «فذكر»
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: "1.2rem" }}>
            <label style={{ display: "block", color: "#F8F6F1", marginBottom: "0.4rem", fontSize: "0.9rem" }}>
              البريد الإلكتروني
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@fadhkur.app"
              required
              style={{
                width: "100%",
                padding: "0.75rem 1rem",
                borderRadius: "8px",
                border: "1px solid #243B6B",
                backgroundColor: "#0E1726",
                color: "#FFFFFF",
                fontSize: "0.95rem"
              }}
            />
          </div>

          <div style={{ marginBottom: "1.8rem" }}>
            <label style={{ display: "block", color: "#F8F6F1", marginBottom: "0.4rem", fontSize: "0.9rem" }}>
              كلمة المرور
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••••••"
              required
              style={{
                width: "100%",
                padding: "0.75rem 1rem",
                borderRadius: "8px",
                border: "1px solid #243B6B",
                backgroundColor: "#0E1726",
                color: "#FFFFFF",
                fontSize: "0.95rem"
              }}
            />
          </div>

          <button
            type="submit"
            disabled={isLoading}
            style={{
              width: "100%",
              padding: "0.85rem",
              borderRadius: "8px",
              border: "none",
              backgroundColor: "#2E9E9E",
              color: "#FFFFFF",
              fontWeight: 600,
              fontSize: "1rem",
              cursor: "pointer",
              transition: "opacity 0.2s",
              opacity: isLoading ? 0.7 : 1
            }}
          >
            {isLoading ? "جارٍ التحقق..." : "دخول إلى لوحة التحكم"}
          </button>
          {errorMessage && (
            <p role="alert" style={{ color: "#FCA5A5", fontSize: "0.85rem", textAlign: "center", marginTop: "1rem" }}>
              {errorMessage}
            </p>
          )}
        </form>

        <p style={{ color: "#5B677A", fontSize: "0.8rem", textAlign: "center", marginTop: "1.5rem" }}>
          جلسات آمنة مشفرة بنظام HttpOnly و SameSite=Lax
        </p>
      </div>
    </div>
  );
}
