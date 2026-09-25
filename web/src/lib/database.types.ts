// Generated from the hosted schema with the Supabase MCP `generate_typescript_types`
// tool (schema only, no data). Regenerate after a migration that changes
// public tables or functions. Do not edit by hand.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          created_at: string
          id: string
          name: string
          owner_id: string
          type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          owner_id?: string
          type: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          owner_id?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          archived: boolean
          builtin_name: string | null
          color: string
          created_at: string
          icon: string
          id: string
          kind: string
          name: string
          owner_id: string
          updated_at: string
        }
        Insert: {
          archived?: boolean
          builtin_name?: string | null
          color: string
          created_at?: string
          icon: string
          id?: string
          kind: string
          name: string
          owner_id?: string
          updated_at?: string
        }
        Update: {
          archived?: boolean
          builtin_name?: string | null
          color?: string
          created_at?: string
          icon?: string
          id?: string
          kind?: string
          name?: string
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      category_rules: {
        Row: {
          category_id: string
          created_at: string
          hit_count: number
          id: string
          keyword: string
          owner_id: string
          updated_at: string
        }
        Insert: {
          category_id: string
          created_at?: string
          hit_count?: number
          id?: string
          keyword: string
          owner_id?: string
          updated_at?: string
        }
        Update: {
          category_id?: string
          created_at?: string
          hit_count?: number
          id?: string
          keyword?: string
          owner_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "category_rules_category_fkey"
            columns: ["owner_id", "category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["owner_id", "id"]
          },
        ]
      }
      profiles: {
        Row: {
          bill_reminder_days_before: number
          bill_reminders_enabled: boolean
          created_at: string
          daily_reminder_enabled: boolean
          daily_reminder_time: string
          id: string
          theme: string
          updated_at: string
        }
        Insert: {
          bill_reminder_days_before?: number
          bill_reminders_enabled?: boolean
          created_at?: string
          daily_reminder_enabled?: boolean
          daily_reminder_time?: string
          id: string
          theme?: string
          updated_at?: string
        }
        Update: {
          bill_reminder_days_before?: number
          bill_reminders_enabled?: boolean
          created_at?: string
          daily_reminder_enabled?: boolean
          daily_reminder_time?: string
          id?: string
          theme?: string
          updated_at?: string
        }
        Relationships: []
      }
      recurring_bills: {
        Row: {
          account_id: string
          amount_paise: number
          category_id: string | null
          created_at: string
          due_day: number
          id: string
          kind: string
          name: string
          owner_id: string
          paid_through_month: string
          reminder_enabled: boolean
          updated_at: string
        }
        Insert: {
          account_id: string
          amount_paise: number
          category_id?: string | null
          created_at?: string
          due_day: number
          id?: string
          kind: string
          name: string
          owner_id?: string
          paid_through_month: string
          reminder_enabled?: boolean
          updated_at?: string
        }
        Update: {
          account_id?: string
          amount_paise?: number
          category_id?: string | null
          created_at?: string
          due_day?: number
          id?: string
          kind?: string
          name?: string
          owner_id?: string
          paid_through_month?: string
          reminder_enabled?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "recurring_bills_account_fkey"
            columns: ["owner_id", "account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["owner_id", "id"]
          },
          {
            foreignKeyName: "recurring_bills_category_fkey"
            columns: ["owner_id", "category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["owner_id", "id"]
          },
        ]
      }
      transactions: {
        Row: {
          account_id: string
          amount_paise: number
          auto_categorized: boolean
          category_id: string | null
          created_at: string
          date: string
          description: string
          id: string
          owner_id: string
          payment_method: string | null
          to_account_id: string | null
          type: string
          updated_at: string
        }
        Insert: {
          account_id: string
          amount_paise: number
          auto_categorized?: boolean
          category_id?: string | null
          created_at?: string
          date?: string
          description?: string
          id?: string
          owner_id?: string
          payment_method?: string | null
          to_account_id?: string | null
          type: string
          updated_at?: string
        }
        Update: {
          account_id?: string
          amount_paise?: number
          auto_categorized?: boolean
          category_id?: string | null
          created_at?: string
          date?: string
          description?: string
          id?: string
          owner_id?: string
          payment_method?: string | null
          to_account_id?: string | null
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "transactions_account_fkey"
            columns: ["owner_id", "account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["owner_id", "id"]
          },
          {
            foreignKeyName: "transactions_category_fkey"
            columns: ["owner_id", "category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["owner_id", "id"]
          },
          {
            foreignKeyName: "transactions_to_account_fkey"
            columns: ["owner_id", "to_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["owner_id", "id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_bill_schedule: {
        Args: { p_today?: string }
        Returns: {
          account_id: string
          amount_paise: number
          category_id: string
          days_until: number
          due_day: number
          id: string
          kind: string
          name: string
          next_due_date: string
          overdue_count: number
          paid_through_month: string
          reminder_enabled: boolean
          status: string
        }[]
      }
      get_month_comparison: {
        Args: { p_month?: string }
        Returns: {
          category_color: string
          category_id: string
          category_name: string
          change_paise: number
          change_pct: number
          kind: string
          last_month_paise: number
          this_month_paise: number
        }[]
      }
      get_month_totals: {
        Args: { p_month?: string }
        Returns: {
          expense_paise: number
          income_paise: number
          last_expense_paise: number
          last_income_paise: number
          last_month: string
          last_net_paise: number
          month: string
          net_paise: number
          uncategorized_count: number
        }[]
      }
      get_monthly_category_totals: {
        Args: { p_from_month?: string; p_to_month?: string }
        Returns: {
          category_color: string
          category_id: string
          category_name: string
          kind: string
          month: string
          total_paise: number
          transaction_count: number
        }[]
      }
      get_monthly_totals: {
        Args: { p_from_month?: string; p_to_month?: string }
        Returns: {
          expense_count: number
          expense_paise: number
          income_count: number
          income_paise: number
          month: string
          net_paise: number
          uncategorized_count: number
        }[]
      }
      mark_bill_paid: {
        Args: {
          p_amount_paise?: number
          p_bill_id: string
          p_month: string
          p_paid_on?: string
          p_payment_method?: string
          p_txn_id?: string
        }
        Returns: {
          already_paid: boolean
          paid_through_month: string
          transaction_id: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}
