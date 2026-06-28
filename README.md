# Yoobble AI

Yoobble AI is a web-based platform built with Flutter and Firebase, designed to streamline content creation (YouTube posts, LinkedIn articles, movie scripts, emails, blog articles) and document analysis. The application features web-focused search engine optimization (SEO), real-time database synchronization via Firestore, and a multi-tier Stripe subscription system with managed trial periods.

---

## Technical Architecture & Dependencies

The architecture is built on a decoupled, reactive model using the following core components:

*   **Frontend Framework:** [Flutter Web](https://flutter.dev) (Responsive UI built with `Sizer`).
*   **State Management:** `Provider` and `MultiProvider` processing live authentication and database streams.
*   **Database & Authentication:** [Cloud Firestore](https://firebase.google.com/docs/firestore) and [Firebase Auth](https://firebase.google.com/docs/auth) for identity and persistent data management.
*   **Payment Infrastructure:** [Stripe REST API](https://stripe.com/docs/api) integration for programmatic pricing setup and checkout redirection.
*   **SEO Optimization:** [MetaSEO](https://pub.dev/packages/meta_seo) for injection of meta tags on web instances.

---

## Core Features

- **Multi-Format AI Generation:** Structured to handle prompts for diverse outputs, including social media posts, email outreach, and scriptwriting.
- **Dynamic Stripe Subscription Flows:** Supports Standard, Pro, and Business tiers (Monthly & Yearly), with automatic product generation on initialization if not present.
- **Trial & Status Checks:** Built-in verification logic for a 5-day free trial, checking Firestore user records to prevent trial abuse.
- **State-Driven Routing:** Reactive application wrapper listening to user authentication state to serve correct views dynamically.
- **Web-Specific SEO Config:** Automated meta-description and tag configuration directly mapping strategic keywords for enhanced search engine visibility.

---

## Configuration & Environment Variables

The application relies on `flutter_dot_json_env` to safely load configuration files.

### 1. Local Configuration File (`local.json`)
Create a `local.json` file in your project assets directory:

```json
{
  "SECRET": "your_stripe_secret_key"
}
```

### 2. Firebase SDK Configuration
Before running, update the web initialization block inside `lib/main.dart` with your project keys:

```dart
await Firebase.initializeApp(
    options: const FirebaseOptions(
        apiKey: "YOUR_API_KEY",
        authDomain: "YOUR_AUTH_DOMAIN",
        projectId: "YOUR_PROJECT_ID",
        storageBucket: "YOUR_STORAGE_BUCKET",
        messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
        appId: "YOUR_APP_ID",
        measurementId: "YOUR_MEASUREMENT_ID"
    )
);
```

---

## Pricing Tiers

The setup manager creates the following product structure inside your Stripe dashboard if not already configured:

| Tier | Monthly Price (USD) | Yearly Price (USD) | Access Level |
| :--- | :--- | :--- | :--- |
| **Standard** | $9.00 / mo | $90.00 / yr | Standard feature access |
| **Pro** | $29.00 / mo | $299.00 / yr | Pro level usage limits |
| **Business** | $99.00 / mo | $999.00 / yr | Full enterprise capabilities |

---

## API Reference

### Google AI Studio (Gemini)
Used for core text and content processing.

```http
  POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
```

| Parameter | Type     | Description                       |
| :-------- | :------- | :-------------------------------- |
| `api_key` | `string` | **Required**. Your Gemini API Key |

### Groq Cloud API
Used for high-speed fallback generation or specific chat completions.

```http
  POST https://api.groq.com/openai/v1/chat/completions
```

| Parameter | Type     | Description                       |
| :-------- | :------- | :-------------------------------- |
| `api_key` | `string` | **Required**. Your Groq API Key   |

---

## Database Document Schema

### Users Collection (`/users/{uid}`)

```typescript
interface UserDocument {
  uid: string;
  name: string;
  email: string;
  photoUrl: string;
  timestamp: FieldValue;
  customerId?: string;          // Stripe Customer ID
  subscriptionId?: string;      // Stripe Subscription ID
  subscriptionStatus?: string;  // 'trial' | 'active' | 'expired'
  planType?: string;            // 'standard' | 'pro' | 'business'
  trialStartDate?: Timestamp;
  trialValidated?: boolean;
  trialEnded?: boolean;
}
```

---

## Getting Started

### Prerequisites
*   Flutter SDK (Stable channel)
*   Dart SDK
*   A Firebase Project
*   A Stripe Developer Account

### Steps
1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/yoobble-ai.git
    cd yoobble-ai
    ```

2.  **Install project dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Place your local configuration:**
    Ensure `local.json` is located in your specified assets folder.

4.  **Execute locally (Web):**
    ```bash
    flutter run -d chrome
    ```

---

## Badges

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Platform-Flutter_Web-blue.svg)](https://flutter.dev)

---

## Feedback

For inquiries, support, or feedback, contact the maintainer at `paolotshiyole9@gmail.com`.
