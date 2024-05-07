#include <stdio.h>
#include <stdint.h>
#include "../include/utils.cuh"
#include <string.h>
#include <stdlib.h>
#include <inttypes.h>

// #define RUN_BONUS
#define MY_BLOCK_SIZE 256
#define MAX_TX_LENGTH 50

__constant__ int d_MAX_NONCE = MAX_NONCE;

BYTE **transactions = NULL;		// list of strings with all transactions
BYTE **h_d_hashed_transactions; // list (on host) of strings (on device) with all hashed transactions
BYTE **d_d_hashed_transactions; // list (on device) of strings (on device) with all hashed transactions

/*
	Computes all combined hashes on 'tree_level'
	The lowest level of the Merkle Tree is 0 (starting with the leaves)
*/
__global__ void merkleTree(BYTE **hashed_tx, int num_tx, int tree_level)
{
	// calculate corresponding index in hashed_tx
	int idx = blockIdx.x * blockDim.x + threadIdx.x;

	// if higher level hash is accumulated at this index
	if (idx % (1 << (tree_level + 1)) == 0)
	{
		int pair_idx = idx + (1 << tree_level);

		// if a pair element exists to combine and rehash with
		if (pair_idx < num_tx)
		{
			BYTE hash1_concat_hash2[SHA256_HASH_SIZE * 2];

			// hash1
			d_strcpy((char *)hash1_concat_hash2, (char *)hashed_tx[idx]);

			// hash1hash2
			d_strcpy((char *)hash1_concat_hash2 + d_strlen((const char *)hashed_tx[idx]), (char *)hashed_tx[pair_idx]);

			// sha256(hash1hash2), placed where hash1 originally was
			apply_sha256(hash1_concat_hash2, d_strlen((const char *)hash1_concat_hash2), hashed_tx[idx], 1);
		}
	}
}

// Searches for all nonces from 1 through MAX_NONCE (inclusive) using CUDA Threads
__global__ void findNonce(BYTE *block_content, size_t current_length, uint64_t *nonce, BYTE *difficulty)
{
	// calculate corresponding nonce value to check in this thread
	int idx = blockIdx.x * blockDim.x + threadIdx.x;
	uint64_t nonce_to_check = idx + 1;

	if (nonce_to_check > d_MAX_NONCE)
		return;

	char nonce_string[NONCE_SIZE];
	int nonce_length = intToString(nonce_to_check, nonce_string);

	BYTE block_content_tmp[BLOCK_SIZE], block_hash[SHA256_HASH_SIZE];

	// block_hash to check
	d_strcpy((char *)block_content_tmp, (char *)block_content);
	d_strcpy((char *)(block_content_tmp + current_length), nonce_string);

	// Check if nonce was not already found
	if (*nonce == 0)
	{	
		// sha256(block_hash)
		apply_sha256(block_content_tmp, d_strlen((const char *)block_content_tmp), block_hash, 1);

		// if nonce was not already found and the block_content satisfies the difficulty
		if (*nonce == 0 && compare_hashes(block_hash, difficulty) <= 0)
			// atomically update nonce only if it was 0 (i.e. it was not found)
			atomicCAS((unsigned long long *)nonce, 0, nonce_to_check);
	}
}

int main(int argc, char **argv)
{
	BYTE top_hash[SHA256_HASH_SIZE], block_content[BLOCK_SIZE];
	BYTE *d_block_content;
	BYTE *d_difficulty;
	BYTE block_hash[SHA256_HASH_SIZE] = "0000000000000000000000000000000000000000000000000000000000000000";
	uint64_t *nonce;
	size_t current_length;
	cudaEvent_t start, stop;

	// Top hash
#ifdef RUN_BONUS
	// we will read all transactions from data/inputs.txt

	/*
		Example inputs.txt (the same example given in the code skel):

		FROM_Alice__TO_Bob__5_BTC
		FROM_Charlie__TO_David__9_BTC
		FROM_Erin__TO_Frank__1_BTC
		FROM_Alice__TO_Frank__3_BTC
	*/

	FILE *in = fopen("data/inputs.txt", "r");
	if (in == NULL)
	{
		printf("Error opening inputs.txt!\n");
		return 1;
	}

	int num_transactions = 0;

	char buffer[MAX_TX_LENGTH];
	while (fgets(buffer, sizeof(buffer), in) != NULL)
	{
		// Remove newline character
		if (buffer[strlen(buffer) - 1] == '\n')
			buffer[strlen(buffer) - 1] = '\0';

		// We don't care about empty lines
		if (strlen(buffer) == 0)
			continue;

		// Reallocate memory for transactions
		transactions = (BYTE **)realloc(transactions, (num_transactions + 1) * sizeof(BYTE *));
		if (transactions == NULL)
		{
			fprintf(stderr, "Memory allocation for transaction list failed.\n");
			return 1;
		}

		// Allocate memory for the current transaction
		transactions[num_transactions] = (BYTE *)malloc(strlen(buffer) + 1); // +1 for null terminator
		if (transactions[num_transactions] == NULL)
		{
			fprintf(stderr, "Memory allocation for transaction string failed.\n");
			return 1;
		}

		// Copy the transaction data into the allocated memory
		strcpy((char *)transactions[num_transactions], buffer);

		// Increment the number of transactions
		++num_transactions;
	}

	// Close the file
	fclose(in);

	// the list itself is on the host
	h_d_hashed_transactions = (BYTE **)malloc(num_transactions * sizeof(BYTE *));

	for (int i = 0; i < num_transactions; ++i)
	{
		// but the pointers inside the list point to memory on the device
		cudaMalloc((void **)&h_d_hashed_transactions[i], SHA256_HASH_SIZE * sizeof(BYTE));

		BYTE hashed_transaction[SHA256_HASH_SIZE];

		// hash the transaction
		apply_sha256(transactions[i], strlen((const char *)transactions[i]), hashed_transaction, 1);

		// copy the data on device
		cudaMemcpy(h_d_hashed_transactions[i], hashed_transaction, SHA256_HASH_SIZE * sizeof(BYTE), cudaMemcpyHostToDevice);
	}
	// this list is on the device
	cudaMalloc(&d_d_hashed_transactions, num_transactions * sizeof(BYTE *));

	// copy the device pointers from the host list
	cudaMemcpy(d_d_hashed_transactions, h_d_hashed_transactions, num_transactions * sizeof(BYTE *), cudaMemcpyHostToDevice);

	int blocks_no_merkle = (num_transactions + MY_BLOCK_SIZE - 1) / MY_BLOCK_SIZE;

	startTiming(&start, &stop);

	// go through all levels of the merkle tree 
	for (int level = 0; 1 << level < num_transactions; ++level)
	{	
		merkleTree<<<blocks_no_merkle, MY_BLOCK_SIZE>>>(d_d_hashed_transactions, num_transactions, level);
		cudaDeviceSynchronize();
	}

	float seconds_merkle = stopTiming(&start, &stop);

	// copy the device list back to the host
	cudaMemcpy(h_d_hashed_transactions, d_d_hashed_transactions, num_transactions * sizeof(BYTE *), cudaMemcpyDeviceToHost);
	// top_hash was accumulated in the first position after combining and rehashing many partial hashes
	cudaMemcpy(top_hash, h_d_hashed_transactions[0], SHA256_HASH_SIZE * sizeof(BYTE), cudaMemcpyDeviceToHost);

	// Print the computed top_hash and the execution time
	FILE *out = fopen("data/outputs.csv", "a");
	if (out != NULL)
	{
		fprintf(out, "%s,%.2f\n", top_hash, seconds_merkle);
		fclose(out);
	}
	else
	{
		printf("Error opening outputs.csv!\n");
	}

	// Free allocated memory used to compute top_hash
	for (int i = 0; i < num_transactions; i++)
	{
		free(transactions[i]);
		cudaFree(h_d_hashed_transactions[i]);
	}
	free(transactions);
	free(h_d_hashed_transactions);
	cudaFree(d_d_hashed_transactions);
#else
	BYTE hashed_tx1[SHA256_HASH_SIZE], hashed_tx2[SHA256_HASH_SIZE], hashed_tx3[SHA256_HASH_SIZE], hashed_tx4[SHA256_HASH_SIZE],
		tx12[SHA256_HASH_SIZE * 2], tx34[SHA256_HASH_SIZE * 2], hashed_tx12[SHA256_HASH_SIZE], hashed_tx34[SHA256_HASH_SIZE],
		tx1234[SHA256_HASH_SIZE * 2];

	apply_sha256(tx1, strlen((const char *)tx1), hashed_tx1, 1);
	apply_sha256(tx2, strlen((const char *)tx2), hashed_tx2, 1);
	apply_sha256(tx3, strlen((const char *)tx3), hashed_tx3, 1);
	apply_sha256(tx4, strlen((const char *)tx4), hashed_tx4, 1);
	strcpy((char *)tx12, (const char *)hashed_tx1);
	strcat((char *)tx12, (const char *)hashed_tx2);
	apply_sha256(tx12, strlen((const char *)tx12), hashed_tx12, 1);
	strcpy((char *)tx34, (const char *)hashed_tx3);
	strcat((char *)tx34, (const char *)hashed_tx4);
	apply_sha256(tx34, strlen((const char *)tx34), hashed_tx34, 1);
	strcpy((char *)tx1234, (const char *)hashed_tx12);
	strcat((char *)tx1234, (const char *)hashed_tx34);
	apply_sha256(tx1234, strlen((const char *)tx34), top_hash, 1);
#endif

	// prev_block_hash + top_hash
	strcpy((char *)block_content, (const char *)prev_block_hash);
	strcat((char *)block_content, (const char *)top_hash);
	current_length = strlen((char *)block_content);

	cudaMalloc((void **)&d_block_content, current_length * sizeof(BYTE));
	cudaMemcpy(d_block_content, block_content, current_length * sizeof(BYTE), cudaMemcpyHostToDevice);

	cudaMalloc((void **)&d_difficulty, SHA256_HASH_SIZE * sizeof(BYTE));
	cudaMemcpy(d_difficulty, DIFFICULTY, SHA256_HASH_SIZE * sizeof(BYTE), cudaMemcpyHostToDevice);

	cudaMallocManaged(&nonce, sizeof(uint64_t));

	*nonce = 0;

	int block_size = MY_BLOCK_SIZE;
	int blocks_no = (MAX_NONCE + block_size - 1) / block_size;

	startTiming(&start, &stop);

	findNonce<<<blocks_no, block_size>>>(d_block_content, current_length, nonce, d_difficulty);

	float seconds = stopTiming(&start, &stop);

	if (*nonce != 0)
	{
		char nonce_string[NONCE_SIZE];
		sprintf(nonce_string, "%lu", *nonce);
		strcat((char *)block_content, nonce_string);
		apply_sha256(block_content, strlen((const char *)block_content), block_hash, 1);
	}
	else
		printf("nonce not found\n");

	printResult(block_hash, *nonce, seconds);

	cudaFree(d_block_content);
	cudaFree(d_difficulty);
	cudaFree(nonce);

	return 0;
}
