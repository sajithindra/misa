# Misa - Real-Time Safety Intelligence App

**Team Name:** Palantir  
**Team Members:** Sajith Surendran, Jobin Mathew  

## About Our Platform

Our platform is an agentic AI-powered real-time safety intelligence system built to protect people at scale. It integrates CCTV networks, drone feeds, and live video streams to detect and identify individuals who appear on authorized watchlists, such as repeat offenders or organized fraud networks.

What makes the system agentic is not just recognition, but autonomous coordination. The AI continuously observes multiple camera feeds, links identities across locations, tracks movement patterns, builds situational timelines, and generates structured intelligence reports without waiting for step-by-step human commands. It determines when to escalate, when to continue monitoring, and when to request operator validation. The system operates as a goal-driven security agent: prevent harm, minimize response time, and maintain traceable documentation.

This platform is built for dense residential communities, apartments, campuses, enterprises, and child-focused institutions. In India alone, millions live in gated communities and high-density housing clusters where shared spaces increase exposure risk.

## What's in this Repository?

This repository contains **Misa**, the Flutter-based mobile client application for the platform. It serves as the mobile edge interface for operators and field personnel. 

Key features implemented in this repository include:
- **Real-Time Camera Streaming:** Captures live video feeds from the mobile device and streams them efficiently over WebSocket to the central backend.
- **Threat Alert Notifications:** Integrates a local notification service to deliver immediate, contextual alerts when the AI identifies persons of interest or requests operator validation.
- **Cross-Platform Support:** Built with Flutter, enabling deployment across Android and iOS devices for security personnel on the ground.
