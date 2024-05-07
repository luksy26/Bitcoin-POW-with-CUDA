#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <ctime>
#include <vector>

// Global vector containing names
std::vector<std::string> names = {
    "Alice", "Bob", "Charlie", "David", "Emma", "Frank", "Grace", "Hannah",
    "Isaac", "Jack", "Katie", "Liam", "Mia", "Nathan", "Olivia", "Peter",
    "Quinn", "Rachel", "Sam", "Taylor", "Ursula", "Victor", "Wendy", "Xander",
    "Yvonne", "Zachary"};

// Function to generate a random name
std::string generateRandomName(const std::string &excludeName)
{
    std::string name;
    do
    {
        name = names[rand() % names.size()];
    } while (name == excludeName);
    return name;
}

// Function to generate a random amount of BTC (between 1 and maxValue)
int generateRandomBTC(int maxValue)
{
    return rand() % maxValue + 1;
}

int main()
{
    int N;
    std::cout << "Enter the number of transactions to generate: ";
    std::cin >> N;

    if (N <= 0)
    {
        std::cerr << "Number must be greater than 0." << std::endl;
        return 1;
    }

    srand(time(0));     // Seed for random number generator
    int maxValue = 100; // Maximum value for the amount of BTC

    // Open a file for writing
    std::ofstream outputFile("inputs.txt");
    if (!outputFile.is_open())
    {
        std::cerr << "Error opening inputs.txt" << std::endl;
        return 1;
    }

    std::string usedToName;
    for (int i = 0; i < N; i++)
    {
        std::string from = generateRandomName("");
        std::string to = generateRandomName(from);
        int amount = generateRandomBTC(maxValue);
        outputFile << "FROM_" << from << "__TO_" << to << "__" << amount << "_BTC\n";
    }

    // Close the file
    outputFile.close();

    std::cout << "Generated " << N << " transactions to inputs.txt" << std::endl;

    return 0;
}
